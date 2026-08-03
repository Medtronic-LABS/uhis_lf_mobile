# Android 16 KB Page Size Compatibility — Native Dependency Audit

## Context

A debug build surfaced Android 15+'s "Android app compatibility" warning dialog, listing ~19 bundled native `.so` libraries that fail the 16 KB memory-page ELF alignment check. Per the dialog's own text, this only fires on debuggable builds as a developer/tester nag — it is not shown to end users on a signed release APK from the Play Store, and it is not currently blocking anything. It is, however, a real forward-compatibility signal: Google has been pushing 16 KB page-size compliance for new app submissions/updates targeting recent API levels, and genuine 16 KB-page hardware exists today even if it's not yet common on real field devices.

Every flagged library was traced to its source and checked against upstream release notes, GitHub issue trackers, and (where available) direct maintainer statements, to separate "already fixed, nothing to do" from "actionable" from "genuinely still broken."

---

## 🔴 Confirmed broken, and actionable

**1. PDFium (`io.github.petretiandrea:android-pdf-viewer:4.0.0`) — dead upstream dependency, no possible fix at this coordinate.**
Flags `libpdfium.so`, `libpdfium.cr.so`, `libicuuc.cr.so`, `libchrome_zlib.cr.so`, `libc++_chrome.cr.so`. This artifact has had exactly two releases ever (`1.0.0` and `4.0.0`, both November 2021) and its GitHub source (`petretiandrea/AndroidPdfViewer`) has been **deleted** — confirmed via a direct 404 on the GitHub API, not just inactive. Its own last-known README said "Looking for new maintainer!" before disappearing entirely. There is no version of this exact library, now or ever, that will carry a 16 KB-aligned PDFium binary.
**Fix:** migrate off this dependency. The community has already moved on to `io.github.oothp:android-pdf-viewer` (latest `3.2.0-beta06`), an actively maintained fork with an explicit 16 KB alignment fix (compressed shared libraries + post-build realignment, AGP 8.13+/NDK r28+) — it's the fork the community `flutter_pdfview` plugin itself switched to for this exact reason. Other options if a bigger change is acceptable: `syncfusion_flutter_pdfviewer` (already updated for the Play 16 KB requirement) or `pdfrx` (uses Android's native `PdfRenderer` API, sidestepping the bundled-PDFium problem entirely). Needs whatever screen currently renders PDFs found and re-verified against the new library's API before swapping.

**2. MediaPipe (`com.google.mediapipe:tasks-genai:0.10.24`) — 16 KB status unconfirmed, likely still unfixed at any available version.**
Flags `libllm_inference_engine_jni.so` (the on-device LLM inference engine, used by the micro-coaching SDK). Google's own MediaPipe team stated explicitly, twice, that the July 2025 16 KB alignment fix (`0.10.26`) shipped **only for `tasks-vision`/`tasks-core`, not `tasks-genai`**. `tasks-genai`'s own version history skips `0.10.26` entirely (`0.10.25 → 0.10.27`), and no subsequent release note confirms the native library was realigned even at the current latest, `0.10.35`. Google's own on-device Gallery app has an open, unresolved tracking issue for the same gap.
**Fix:** bump `0.10.24 → 0.10.35` regardless (reasonable hygiene, and it's possible the underlying build toolchain change was inherited even without an explicit release note) — but do not report this as "fixed" without independently verifying: `unzip -p tasks-genai-0.10.35.aar libllm_inference_engine_jni.so | readelf -lW -` and confirm the `LOAD` segment alignment reads `0x4000`, not `0x1000`/`0x2000`.

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

## Recommendation

Two real pieces of work here, in priority order:
1. **Migrate off `io.github.petretiandrea:android-pdf-viewer`** — it's not just unaligned, it's an abandoned dependency with a deleted source repo, which is a maintenance risk independent of the 16 KB issue.
2. **Bump `com.google.mediapipe:tasks-genai` to `0.10.35`**, then verify the bundled `.so` alignment directly with `readelf` rather than assuming it inherited the vision/core fix.

Everything else is either already fine (SQLCipher, CameraX) or has no available fix yet (ML Kit) — tracked here for visibility, not immediate action.
