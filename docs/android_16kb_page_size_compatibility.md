# Android 16 KB Page Size Compatibility — Native Dependency Audit

## Context

A debug build surfaced Android 15+'s "Android app compatibility" warning dialog, listing ~19 bundled native `.so` libraries that fail the 16 KB memory-page ELF alignment check. Per the dialog's own text, this only fires on debuggable builds as a developer/tester nag — it is not shown to end users on a signed release APK from the Play Store, and it is not currently blocking anything. It is, however, a real forward-compatibility signal: Google has been pushing 16 KB page-size compliance for new app submissions/updates targeting recent API levels, and genuine 16 KB-page hardware exists today even if it's not yet common on real field devices.

Every flagged library was traced to its source and checked against upstream release notes, GitHub issue trackers, and (where available) direct maintainer statements, to separate "already fixed, nothing to do" from "actionable" from "genuinely still broken."

---

## 🔴 Confirmed broken, and actionable

**1. PDFium (`io.github.petretiandrea:android-pdf-viewer:4.0.0`) — dead upstream dependency, and not fixable from this repo at all.**
Flags `libpdfium.so`, `libpdfium.cr.so`, `libicuuc.cr.so`, `libchrome_zlib.cr.so`, `libc++_chrome.cr.so`. This artifact has had exactly two releases ever (`1.0.0` and `4.0.0`, both November 2021) and its GitHub source (`petretiandrea/AndroidPdfViewer`) has been **deleted** — confirmed via a direct 404 on the GitHub API, not just inactive. Its own last-known README said "Looking for new maintainer!" before disappearing entirely. There is no version of this exact library, now or ever, that will carry a 16 KB-aligned PDFium binary.
**Where it's actually used (traced by decompiling the AAR — see below): nowhere in this repo.** `android/app/build.gradle.kts:105` declares it only because it's a transitive runtime requirement of the prebuilt `micro-coaching-sdk.aar` — the AAR's own `com.medtroniclabs.microcoaching.ui.document.PdfPagerScreenKt`/`DocumentPreviewActivity` classes import `com.github.barteksc.pdfviewer.PDFView` directly to preview coaching/training PDFs. Grepping every `.kt`/`.java` file in `android/app/src/main` for `pdf`/`petretiandrea`/`barteksc` returns nothing — the only call site is compiled into the closed-source AAR binary.
**Fix:** this cannot be migrated from `uhis_lf_mobile`. Swapping the Maven coordinate here would just change which version we declare to satisfy the AAR's linker requirement — the AAR's own compiled bytecode still calls the old `com.github.barteksc.pdfviewer.PDFView` API and would need to be recompiled against a different library. The actual fix (migrate to `io.github.oothp:android-pdf-viewer` or similar, or drop bundled-PDFium entirely in favor of Android's native `PdfRenderer`) has to happen in **`Medtronic-LABS/spice-coaching`** (the source repo that builds `micro-coaching-sdk.aar`), then flow down here as a new AAR version.

**2. MediaPipe (`com.google.mediapipe:tasks-genai:0.10.24`) — 16 KB status unconfirmed, likely still unfixed at any available version, and same "not fixable here" situation as PDFium.**
Flags `libllm_inference_engine_jni.so` (the on-device LLM inference engine). Google's own MediaPipe team stated explicitly, twice, that the July 2025 16 KB alignment fix (`0.10.26`) shipped **only for `tasks-vision`/`tasks-core`, not `tasks-genai`**. `tasks-genai`'s own version history skips `0.10.26` entirely (`0.10.25 → 0.10.27`), and no subsequent release note confirms the native library was realigned even at the current latest, `0.10.35`. Google's own on-device Gallery app has an open, unresolved tracking issue for the same gap.
**Where it's actually used:** also nowhere in this repo's own Kotlin/Dart code. Decompiling `micro-coaching-sdk.aar` shows `com.medtroniclabs.microcoaching.ai.inference.GemmaService`/`InferenceRouter`/`ModelRuntime`/`ModelCatalog` — the on-device Gemma model backing the coaching chat — calling MediaPipe directly. Our own `MicroCoachingPlugin.kt`/`MainApplication.kt` only bridge Flutter to the AAR's Kotlin API; neither references MediaPipe.
**Fix:** same constraint as PDFium — bumping `0.10.24` in our `build.gradle.kts` only changes what we declare to link against, and risks an API mismatch against whatever the AAR's `GemmaService` was actually compiled against. The real fix (bump the dependency, then verify with `readelf -lW` that `libllm_inference_engine_jni.so`'s `LOAD` segment aligns to `0x4000`) has to happen in `spice-coaching`, in the same AAR rebuild as the PDFium fix.

---

## 🟡 Disputed — Google claims fixed, independent reports through late 2025 disagree, no upgrade path exists

**3. Google ML Kit (`google_mlkit_text_recognition:16.0.1`, `google_mlkit_barcode_scanning:17.3.0`, `com.google.mlkit:translate:17.0.3`).**
Flags `libmlkit_google_ocr_pipeline.so`, `libbarhopper_v3.so`, `libtranslate_jni.so`. Google's ML Kit release notes claim all three received 16 KB alignment in **August 2024**, and **the app is already pinned to those exact "fixed" versions** — there is no newer release to upgrade to for any of them (`translate:17.0.3` is still the latest published version, period).
In practice, `barcode-scanning`'s `libbarhopper_v3.so` (and possibly a co-bundled `libimage_processing_util_jni.so` from `vision-common`) has multiple credible, recent bug reports (through December 2025) still showing misaligned `LOAD` segments under AGP 8.5+, with no visible Google response confirming or refuting this in any of the threads. `translate` has no disputing reports found — but that may just mean fewer people exercise on-device translate heavily enough to hit it, not that it's confirmed clean.
**No fix available right now.** This is stuck pending a Google-side release; flagging as an open risk to track, not something actionable via a dependency bump today.

---

## 🟢 Confirmed fixed — no action needed

**4. SQLCipher (`sqflite_sqlcipher:3.4.0`).** Resolves to `net.zetetic:sqlcipher-android:4.10.0` (confirmed by reading the plugin's own `build.gradle`), well past the `4.6.1` release (Aug 2024) where Zetetic's own engineers confirmed 16 KB page-size support landed. (One isolated community report from mid-2025 claims the issue persisting — noted for awareness, but unconfirmed and inconsistent with the vendor's own statement and our resolved version.)

**5. CameraX (`camera:0.12.0+1`, via `camera_android_camerax`).** Resolves to CameraX ~1.6.1, well past `1.4.0` (Oct 2024), where the CameraX team directly confirmed (Google Groups) the `libimage_processing_util_jni.so` alignment fix landed after being pulled from a planned 1.3.5 patch.

**Note:** both of these are "fixed as currently resolved" — worth a `./gradlew :app:dependencies` check at some point to confirm nothing elsewhere in the project pins an older transitive version, since Gradle can silently resolve to a stale version if something else in the dependency graph forces it.

---

## Where PDFium and MediaPipe are actually used

Both looked, at first pass, like our own dependencies to fix — they're declared in our own `android/app/build.gradle.kts`. Tracing actual call sites tells a different story.

**Method:** `android/app/src/main` has exactly 3 Kotlin/Java files (`MainActivity.kt`, `MicroCoachingPlugin.kt`, `MainApplication.kt`, plus Flutter's generated plugin registrant) — grepping all of them for `pdf`, `petretiandrea`, `barteksc`, and `mediapipe`/`llminference` returns nothing. The dependencies exist purely to satisfy the linker for `android/app/libs/micro-coaching-sdk.aar`, a prebuilt binary (AARs don't bundle their own transitive dependencies, so the consuming app has to declare them). To find the real usage, the AAR was decompiled directly:

```bash
unzip -o micro-coaching-sdk.aar -d extracted
unzip -o extracted/classes.jar -d extracted/classes
grep -rla "petretiandrea\|PDFView\|pdfium" extracted/classes      # PDFium usage
grep -rlai "mediapipe\|llm_inference\|LlmInference" extracted/classes  # MediaPipe usage
```

**Result — both libraries are used exclusively inside the AAR's own compiled classes, not anywhere in this repo:**

| Library | Class(es) inside the AAR calling it | What it's for |
|---|---|---|
| PDFium (`android-pdf-viewer`) | `com.medtroniclabs.microcoaching.ui.document.PdfPagerScreenKt`, `DocumentPreviewActivity` — directly import `com.github.barteksc.pdfviewer.PDFView` | Previewing coaching/training PDF documents inside the micro-coaching feature |
| MediaPipe (`tasks-genai`) | `com.medtroniclabs.microcoaching.ai.inference.GemmaService`, `InferenceRouter`, `ModelRuntime`, `ModelCatalog` | The on-device Gemma LLM powering the coaching chat |

**Why this matters:** neither library can be swapped or safely version-bumped from `uhis_lf_mobile` alone. Changing the Maven coordinate in our `build.gradle.kts` only changes what we declare to link against at build time — the AAR's own compiled bytecode still calls whatever API surface it was originally compiled against, and a version mismatch there risks a runtime `NoSuchMethodError`/`ClassNotFoundException` rather than a clean fix. The actual source lives in a separate repo — **`Medtronic-LABS/spice-coaching`** ("Codebase for micro coaching SDK for Spice") — which builds and ships `micro-coaching-sdk.aar`. Fixing either library means a change there, followed by a new AAR drop into this repo.

---

## Recommendation

There is no in-repo code fix available for the two actionable items — both route through a separate repo:

1. **File the PDFium and MediaPipe findings against `Medtronic-LABS/spice-coaching`**, since that's where `micro-coaching-sdk.aar` is actually built. That repo's maintainers would need to: migrate off `io.github.petretiandrea:android-pdf-viewer` (dead, deleted source — e.g. to `io.github.oothp:android-pdf-viewer` or Android's native `PdfRenderer`), and bump `com.google.mediapipe:tasks-genai` past `0.10.24`, verifying `libllm_inference_engine_jni.so`'s alignment with `readelf -lW` afterward rather than assuming it inherited the vision/core-only fix.
2. Once `spice-coaching` ships an updated AAR, bump `android/app/libs/micro-coaching-sdk.aar` here and re-run the compatibility check to confirm both libraries drop off the flagged list.

Everything else is either already fine (SQLCipher, CameraX) or has no available fix yet (ML Kit) — tracked here for visibility, not immediate action.
