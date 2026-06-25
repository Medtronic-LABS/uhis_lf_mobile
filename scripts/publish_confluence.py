#!/usr/bin/env python3
"""
Publishes UHIS Leapfrog Mobile developer docs to Confluence.

Creates/updates pages under the configured parent page. Run locally or via
GitHub Actions (see .github/workflows/confluence-docs.yml).

Required env vars:
  CONFLUENCE_BASE_URL       e.g. https://mdtlabs.atlassian.net
  CONFLUENCE_EMAIL          Atlassian account email
  CONFLUENCE_API_TOKEN      Atlassian API token (not password)
  CONFLUENCE_SPACE_KEY      Space key, e.g. UNL
  CONFLUENCE_PARENT_PAGE_ID Parent page numeric ID, e.g. 712540457
"""

import os
import subprocess
import datetime
import sys

try:
    from atlassian import Confluence
except ImportError:
    print("Install deps: pip install atlassian-python-api", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
BASE_URL = os.environ["CONFLUENCE_BASE_URL"]
EMAIL = os.environ["CONFLUENCE_EMAIL"]
TOKEN = os.environ["CONFLUENCE_API_TOKEN"]
SPACE = os.environ.get("CONFLUENCE_SPACE_KEY", "UNL")
PARENT_ID = os.environ.get("CONFLUENCE_PARENT_PAGE_ID", "712540457")

conf = Confluence(url=BASE_URL, username=EMAIL, password=TOKEN, cloud=True)

TODAY = datetime.date.today().isoformat()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def h(level: int, text: str) -> str:
    return f"<h{level}>{text}</h{level}>"


def p(text: str) -> str:
    return f"<p>{text}</p>"


def code(content: str, language: str = "bash") -> str:
    return (
        f'<ac:structured-macro ac:name="code" ac:schema-version="1">'
        f'<ac:parameter ac:name="language">{language}</ac:parameter>'
        f"<ac:plain-text-body><![CDATA[{content}]]></ac:plain-text-body>"
        f"</ac:structured-macro>"
    )


def table(headers: list[str], rows: list[list[str]]) -> str:
    head = "<tr>" + "".join(f"<th><strong>{h}</strong></th>" for h in headers) + "</tr>"
    body = "".join(
        "<tr>" + "".join(f"<td>{c}</td>" for c in row) + "</tr>" for row in rows
    )
    return f"<table>{head}{body}</table>"


def info(text: str) -> str:
    return (
        f'<ac:structured-macro ac:name="info" ac:schema-version="1">'
        f"<ac:rich-text-body><p>{text}</p></ac:rich-text-body>"
        f"</ac:structured-macro>"
    )


def warning(text: str) -> str:
    return (
        f'<ac:structured-macro ac:name="warning" ac:schema-version="1">'
        f"<ac:rich-text-body><p>{text}</p></ac:rich-text-body>"
        f"</ac:structured-macro>"
    )


def upsert(title: str, body: str, parent_id: str = PARENT_ID) -> None:
    existing = conf.get_page_by_title(space=SPACE, title=title)
    if existing:
        conf.update_page(page_id=existing["id"], title=title, body=body)
        print(f"  ✓ updated  → {title}")
    else:
        conf.create_page(space=SPACE, title=title, body=body, parent_id=parent_id)
        print(f"  ✓ created  → {title}")


# ---------------------------------------------------------------------------
# Page content builders
# ---------------------------------------------------------------------------

def page_home() -> str:
    return (
        h(1, "UHIS Leapfrog Mobile")
        + p(
            "Offline-first Flutter 3.x app for UHIS Shasthya Shebikas (frontline community health workers). "
            "Integrates AI-assisted triage, clinical decision support, household management, and a tiered mission dashboard."
        )
        + p(
            "<strong>Repository:</strong> "
            '<a href="https://github.com/Medtronic-LABS/uhis_lf_mobile">Medtronic-LABS/uhis_lf_mobile</a>'
        )
        + table(
            ["Layer", "Value"],
            [
                ["Framework", "Flutter 3.x · Dart"],
                ["State management", "Provider (ChangeNotifier)"],
                ["Routing", "GoRouter (StatefulShellRoute)"],
                ["Local DB", "SQLCipher-encrypted SQLite via sqflite_sqlcipher"],
                ["DB file", "uhis_offline.db — per-device key from Android KeyStore"],
                ["Auth", "JWT bearer token · flutter_secure_storage"],
                ["Schema version", "v13"],
                ["Min Android SDK", "API 21 (Lollipop)"],
                ["Password hash", "HmacSHA512(password, hashKey) — hashKey via --dart-define"],
            ],
        )
        + h(2, "Pages in this space")
        + table(
            ["Page", "What it covers"],
            [
                ["Developer Setup Guide", "Clone, configure, run locally, build for Android"],
                ["Architecture Overview", "Layers, state management, routing, reactive patterns"],
                ["Screens &amp; Navigation", "All screens, GoRouter routes, shell tabs"],
                ["Offline Sync Model", "Sync protocol, entity ordering, conflict strategy"],
                ["Database Schema", "All SQLite tables, migrations v1–v13, encryption"],
                ["Assessment &amp; CDS", "3-step visit flow, section registry, CDSS algorithms, CDS rules"],
                ["API Reference", "All offline-service endpoints used by the app"],
                ["Changelog", "Auto-generated from git history"],
            ],
        )
        + p(f"<em>Last published: {TODAY}</em>")
    )


def page_developer_setup() -> str:
    return (
        h(1, "Developer Setup Guide")
        + h(2, "Prerequisites")
        + table(
            ["Tool", "Version", "Install"],
            [
                ["Flutter", "3.x stable", '<a href="https://docs.flutter.dev/get-started/install">flutter.dev</a>'],
                ["Dart", "bundled with Flutter", "—"],
                ["Android Studio", "latest", '<a href="https://developer.android.com/studio">developer.android.com</a>'],
                ["Android SDK", "API 34", "via Android Studio SDK Manager"],
                ["Java", "17 (for Gradle)", "brew install openjdk@17"],
                ["adb", "any", "bundled with Android Studio"],
            ],
        )
        + h(2, "Clone &amp; configure")
        + code(
            "git clone https://github.com/Medtronic-LABS/uhis_lf_mobile.git\n"
            "cd uhis_lf_mobile\n"
            "flutter pub get"
        )
        + h(2, "Run on device / emulator")
        + code(
            "# List connected devices\n"
            "flutter devices\n\n"
            "# Run against the dev backend (Android emulator localhost alias)\n"
            "flutter run \\\n"
            "  --dart-define=API_BASE_URL=http://10.0.2.2:80 \\\n"
            "  --dart-define=PASSWORD_HASH_KEY=<hash_key>\n\n"
            "# Run against a device on LAN (replace with your machine IP)\n"
            "flutter run \\\n"
            "  --dart-define=API_BASE_URL=http://192.168.1.100:80 \\\n"
            "  --dart-define=PASSWORD_HASH_KEY=<hash_key>"
        )
        + p("<code>10.0.2.2</code> is the Android emulator alias for localhost on the host machine.")
        + h(2, "Build APK")
        + code(
            "flutter build apk --release \\\n"
            "  --dart-define=API_BASE_URL=https://your-server.example.com \\\n"
            "  --dart-define=PASSWORD_HASH_KEY=<hash_key>\n"
            "# Output: build/app/outputs/flutter-apk/app-release.apk"
        )
        + h(2, "Dev credentials")
        + warning(
            "Dev-only credentials are not stored in source code. "
            "Get them from your team lead or the internal credential store."
        )
        + table(
            ["Field", "Where to find it"],
            [
                ["Username", "Internal credential store / team lead"],
                ["Password", "Internal credential store / team lead"],
                ["Backend hash key (PASSWORD_HASH_KEY)", "Internal credential store / team lead"],
            ],
        )
        + h(2, "Run tests")
        + code(
            "flutter test                          # all tests\n"
            "flutter test test/core/cdss/          # CDSS algorithm tests\n"
            "flutter test test/core/db/            # DAO tests (uses sqflite_ffi)"
        )
        + h(2, "Environment variables (--dart-define)")
        + table(
            ["Key", "Default", "Description"],
            [
                ["API_BASE_URL", "http://10.0.2.2:80", "Backend base URL"],
                ["PASSWORD_HASH_KEY", "(from team / internal store)", "HmacSHA512 salt for login — do not commit"],
            ],
        )
        + info("All config is accessed via <code>lib/core/config/app_config.dart</code>. Never hardcode these values.")
        + h(2, "Common issues")
        + table(
            ["Problem", "Fix"],
            [
                ["<code>file is not a database</code> on first open", "Stale unencrypted DB from old build — app auto-recovers (deletes + recreates on open)."],
                ["Login returns 401", "Backend hash key mismatch — check <code>--dart-define=PASSWORD_HASH_KEY</code>."],
                ["Sync hangs at 0%", "Backend unreachable — verify <code>API_BASE_URL</code> and that the UHIS stack is running."],
                ["Gradle build fails", "Ensure Java 17 on PATH; run <code>./gradlew --stop</code> then retry."],
                ["<code>splashBg not found</code> (AAPT)", "<code>android/app/src/main/res/values/colors.xml</code> must exist with <code>splashBg = #1B2B5E</code>."],
            ],
        )
    )


def page_architecture() -> str:
    return (
        h(1, "Architecture Overview")
        + h(2, "Guiding principles")
        + "<ul>"
        + "<li><strong>Offline-first.</strong> App is fully functional without network. All reads from local SQLite; writes local-first, sync opportunistically.</li>"
        + "<li><strong>Strict layering.</strong> UI ↔ state/domain ↔ repository/data ↔ transport. Widgets carry no business logic; repositories carry no UI.</li>"
        + "<li><strong>Single truth per entity.</strong> Every constant, string, business rule has exactly one home.</li>"
        + "</ul>"
        + h(2, "Layer diagram")
        + code(
            "┌─────────────────────────────────────────────────────┐\n"
            "│  UI Layer (lib/features/*_screen.dart, widgets/)    │\n"
            "│  Flutter widgets · GoRouter · Provider consumers    │\n"
            "├─────────────────────────────────────────────────────┤\n"
            "│  State / Domain Layer                               │\n"
            "│  ChangeNotifier providers, *_repository.dart        │\n"
            "├─────────────────────────────────────────────────────┤\n"
            "│  Data Layer (lib/core/db/*_dao.dart)                │\n"
            "│  SQLite DAOs · sqflite_sqlcipher                    │\n"
            "├─────────────────────────────────────────────────────┤\n"
            "│  Transport Layer (lib/core/api/*_client.dart)       │\n"
            "│  Dart http · JWT bearer token                       │\n"
            "└─────────────────────────────────────────────────────┘\n"
            "         ↕ JSON over HTTP\n"
            "┌────────────────────────┐\n"
            "│  UHIS Backend          │\n"
            "│  offline-service :80   │\n"
            "└────────────────────────┘",
            language="text",
        )
        + h(2, "State management — Provider")
        + table(
            ["Provider", "Type", "Purpose"],
            [
                ["AppDatabase", "singleton", "SQLite handle — injected into all DAOs"],
                ["MissionDashboardRepository", "ChangeNotifier", "Patient queue, composite scoring, village filter"],
                ["SyncService", "ChangeNotifier", "Full / warm sync progress + push queue"],
                ["AuthRepository", "—", "JWT token, login/logout"],
                ["VisitController", "ChangeNotifier", "Active 3-step assessment session state"],
            ],
        )
        + h(2, "Routing — GoRouter")
        + p("Root shell: <code>StatefulShellRoute.indexedStack</code> — persistent tab state across bottom-nav switches.")
        + table(
            ["Tab", "Route", "Screen"],
            [
                ["0", "/", "MissionDashboardScreen"],
                ["1", "/patients", "HouseholdListScreen"],
                ["2", "/referrals", "ReferralListScreen"],
            ],
        )
        + p("Deep routes (full-screen, outside shell):")
        + table(
            ["Route", "Screen"],
            [
                ["/login", "LoginScreen"],
                ["/sync", "SyncProgressScreen"],
                ["/pin/setup", "PIN creation"],
                ["/pin/unlock", "PIN unlock"],
                ["/visit/:id/assessment", "SectionedAssessmentScreen"],
                ["/patient/:id", "PatientDetailScreen"],
                ["/household/:id", "HouseholdDetailScreen"],
            ],
        )
        + h(2, "Reactive dashboard pattern")
        + p(
            "<code>MissionDashboardRepository</code> owns a <code>ValueNotifier&lt;int&gt; _changes</code>. "
            "Any mutation (sync, visit completion, manual refresh) increments it. The screen listens and reloads."
        )
        + table(
            ["Method", "Notification", "When to use"],
            [
                ["refresh()", "fires _changes once after await", "Pull-to-refresh, post-sync"],
                ["clearCache()", "fires _changes immediately", "After visit completion"],
                ["_invalidateCache()", "silent — no notification", "Internal use before refresh()"],
            ],
        )
        + h(2, "Security model")
        + table(
            ["Concern", "Mechanism"],
            [
                ["DB encryption", "SQLCipher — per-device 256-bit key in Android EncryptedSharedPreferences (KeyStore-backed)"],
                ["API auth", "JWT bearer token in Authorization header, stored in flutter_secure_storage"],
                ["Password hashing", "HmacSHA512(plaintext, hashKey) — hashKey injected at build time via --dart-define"],
                ["Session token", "Stored on device; password / hash never stored"],
                ["Stale DB recovery", "AppDatabase.open() catches SQLITE_NOTADB (26), deletes stale file, recreates encrypted DB"],
            ],
        )
    )


def page_screens() -> str:
    return (
        h(1, "Screens &amp; Navigation")
        + h(2, "Mission Dashboard (/)")
        + p("<em>lib/features/dashboard/mission_dashboard_screen.dart</em>")
        + p("The primary daily workflow screen. Shows a tiered, AI-sorted patient queue.")
        + "<ul>"
        + "<li><strong>Village chip row</strong> — 'WHICH VILLAGE ARE YOU VISITING?' — filters queue. Hidden when ≤1 village.</li>"
        + "<li><strong>Need filter chips</strong> — filter by programme category.</li>"
        + "<li><strong>3 tiers</strong> — CRITICAL (red) → OVERDUE (amber) → UPCOMING (blue).</li>"
        + "<li><strong>'✦ AI sorted' badge</strong> — shown when composite scoring is active.</li>"
        + "<li>Pull-to-refresh calls <code>MissionDashboardRepository.refresh()</code>.</li>"
        + "</ul>"
        + h(3, "Composite scoring factors")
        + table(
            ["Factor", "Points"],
            [
                ["Base tier (CRITICAL / OVERDUE / UPCOMING)", "100 / 50 / 10"],
                ["Pregnant patient (ANC/PNC enrolled or snapshot)", "+10"],
                ["Near-term ANC", "+15"],
                ["High-risk pregnancy gap", "+20"],
                ["PNC window", "+12"],
                ["Had delivery complications", "+10"],
                ["CQL CRITICAL alert", "+25"],
                ["Days overdue (capped)", "+0–15"],
            ],
        )
        + h(2, "Patients (/patients)")
        + p("<em>lib/features/household/household_list_screen.dart</em>")
        + p("Two sub-tabs: <strong>Members</strong> | <strong>Households</strong>.")
        + "<ul>"
        + "<li>Village chip row — sourced from <code>MemberDao.getDistinctVillages()</code>.</li>"
        + "<li>Search bar — fuzzy name search.</li>"
        + "</ul>"
        + h(2, "Tasks (/referrals)")
        + p("<em>lib/features/referral/referral_list_screen.dart</em>")
        + p("Two sub-tabs: <strong>Visits</strong> | <strong>Referrals</strong>.")
        + "<ul>"
        + "<li>Visits: village + tier chips. Follow-up patients.</li>"
        + "<li>Referrals: active referrals, SLA breach countdown, escalation level.</li>"
        + "</ul>"
        + h(2, "Login (/login)")
        + p("Multipart form POST to <code>/offline-service/offline-sync/login</code>. JWT returned in <code>Authorization</code> response header.")
        + h(2, "Sync (/sync)")
        + p("Full sync on first login; warm sync on subsequent opens. Downloads all entities in FK-safe order.")
        + h(2, "PIN (/pin/setup, /pin/unlock)")
        + p("6-digit PIN. Stored hashed in <code>flutter_secure_storage</code>. Required after inactivity timeout.")
        + h(2, "Assessment (/visit/:id/assessment)")
        + p("3-step visit form. See <strong>Assessment &amp; CDS</strong> page for full details.")
    )


def page_offline_sync() -> str:
    return (
        h(1, "Offline Sync Model")
        + h(2, "Sync types")
        + table(
            ["Type", "When", "What"],
            [
                ["Full sync", "First login after install / manual wipe", "Downloads all entities for the SK's catchment"],
                ["Warm sync", "Every subsequent app open", "Incremental — entities updated since last sync timestamp"],
                ["Post-assessment push", "After a completed visit", "Uploads assessment + encounter to server"],
            ],
        )
        + h(2, "Full sync entity order")
        + p("Order matters — foreign key integrity requires parents before children:")
        + code(
            "1. Households\n"
            "2. Members           (FK → households)\n"
            "3. Patients          (FK → members)\n"
            "4. Patient programmes\n"
            "5. Follow-ups\n"
            "6. Immunisations\n"
            "7. Assessments\n"
            "8. Referrals\n"
            "9. Referral status events\n"
            "10. Pregnancy snapshots\n"
            "11. Treatment presence\n"
            "12. AI suggestions cache",
            language="text",
        )
        + h(2, "Key sync endpoints")
        + table(
            ["Entity", "Endpoint"],
            [
                ["Login", "POST /offline-service/offline-sync/login (multipart: username, password)"],
                ["Household download", "GET /offline-service/offline-sync/household-list"],
                ["Member download", "GET /offline-service/offline-sync/member-list"],
                ["Patient download", "GET /offline-service/offline-sync/patient-list"],
                ["Assessment history", "GET /offline-service/offline-sync/member-assessment-history"],
                ["Assessment upload", "POST /offline-service/offline-sync/assessment-upload"],
            ],
        )
        + h(2, "Timestamps and deduplication")
        + "<ul>"
        + "<li>Every entity carries <code>updated_at</code> (epoch ms). Warm sync fetches <code>updated_at &gt; last_sync_time</code>.</li>"
        + "<li><code>sync_meta</code> table stores <code>last_sync_time</code> and <code>last_full_sync_at</code> per entity class.</li>"
        + "<li>Upsert strategy: <code>INSERT OR REPLACE</code> — idempotent, safe to re-run.</li>"
        + "</ul>"
        + h(2, "Tier inference for new patients")
        + p("<code>visitDate</code> always present in assessment history → seeds <code>last_visit_at</code>.")
        + p("<code>nextFollowUpDate</code> sparse (ANC/PNC only). When absent, <code>_inferDueAt()</code> uses:")
        + p("<code>due_at = last_visit_at + programme_default_interval</code>")
        + table(
            ["Programme", "Default interval"],
            [
                ["NCD", "30 days"],
                ["ANC", "14 days"],
                ["PNC", "7 days"],
                ["TB", "30 days"],
                ["IMCI", "7 days"],
            ],
        )
        + info("Patients without <code>last_visit_at</code> show as <strong>upcoming</strong> until first assessment history sync.")
        + h(2, "Offline write path")
        + code(
            "1. SK completes assessment\n"
            "   → VisitController saves to encounters + local_assessments (sync_status='pending')\n"
            "2. On next connectivity\n"
            "   → SyncService.pushPending() uploads pending local assessments\n"
            "3. On success\n"
            "   → sync_status='synced', fhir_id populated from server response\n"
            "4. MissionDashboardRepository.clearCache() fires → refreshes queue",
            language="text",
        )
        + h(2, "Conflict strategy")
        + p(
            "Last-write-wins at server. The SK app is the sole writer for assessments. "
            "For master data (households, members, patients) the server is authoritative — "
            "local state is overwritten on next full sync."
        )
    )


def page_database() -> str:
    return (
        h(1, "Database Schema")
        + info("File: <code>uhis_offline.db</code> — SQLCipher encrypted, per-device key from Android KeyStore. Source: <code>lib/core/db/app_database.dart</code>.")
        + h(2, "Migration history")
        + table(
            ["Version", "What changed"],
            [
                ["v1", "Initial schema: households, members, patients, sync_meta"],
                ["v2", "patient_programmes, follow_ups, immunisations, assessments; risk columns on patients"],
                ["v3", "Referral SLA tables (referrals, referral_status_events, notification_log)"],
                ["v4", "Encounters table — offline-first visit capture"],
                ["v5", "local_assessments — offline assessment drafts pending upload"],
                ["v6", "is_household_head, is_pregnant, relation on members"],
                ["v7", "Extended fields: fhir_id, GPS, WASH on households; signature, mother refs on members"],
                ["v8", "patient_pregnancy_snapshot, patient_treatment_presence; extra columns on follow_ups"],
                ["v9", "assessment_draft — in-progress assessment survives backgrounding"],
                ["v10", "ai_suggestions — pathway suggestion cache per member"],
                ["v11", "eval_log — AI model evaluation shadow dataset"],
                ["v12", "village_name, sub_village_id/name, shasthya_shebika_id on members"],
                ["v13", "village_name on patients"],
            ],
        )
        + h(2, "Key tables")
        + h(3, "households")
        + table(
            ["Column", "Type", "Notes"],
            [
                ["id", "TEXT PK", "server ID"],
                ["name", "TEXT", "household head name"],
                ["village_id / village", "TEXT", ""],
                ["member_count", "INTEGER", ""],
                ["latitude / longitude", "REAL", "GPS"],
                ["is_owned_an_improved_latrine / hand_washing / bed_net", "INTEGER (bool)", "WASH indicators"],
                ["sync_status", "TEXT", "'Success' default"],
                ["raw_json", "TEXT", "full server payload"],
            ],
        )
        + h(3, "members")
        + table(
            ["Column", "Type", "Notes"],
            [
                ["id", "TEXT PK", ""],
                ["household_id", "TEXT", "FK → households"],
                ["patient_id", "TEXT", "FK → patients (if enrolled)"],
                ["name / gender / dob", "TEXT", ""],
                ["village_id / village_name", "TEXT", ""],
                ["sub_village_id / sub_village_name", "TEXT", "added v12"],
                ["shasthya_shebika_id", "TEXT", "assigned SK, added v12"],
                ["is_pregnant / is_household_head", "INTEGER (bool)", ""],
                ["relation", "TEXT", "relation to head"],
            ],
        )
        + h(3, "patients")
        + table(
            ["Column", "Type", "Notes"],
            [
                ["id", "TEXT PK", "server patient ID"],
                ["risk_score", "INTEGER", "composite score 0–100"],
                ["risk_band", "TEXT", "LOW / MEDIUM / HIGH / CRITICAL"],
                ["last_visit_at / next_due_at", "INTEGER", "epoch ms"],
                ["missed_visit_count", "INTEGER", ""],
                ["village_name", "TEXT", "added v13"],
            ],
        )
        + h(3, "patient_programmes")
        + p("Many-to-many: patient ↔ active programme enrolments. PK = (patient_id, programme).")
        + p("Programme values: <code>imci, anc, pnc, ncd, tb, epi, nutrition, familyPlanning, cataract, eyeCare</code>")
        + h(3, "local_assessments")
        + table(
            ["Column", "Type", "Notes"],
            [
                ["id", "TEXT PK", "local UUID"],
                ["patient_id", "TEXT", ""],
                ["assessment_type", "TEXT", "NCD, ANC, PNC, etc."],
                ["assessment_details", "TEXT", "JSON blob"],
                ["sync_status", "TEXT", "pending → synced"],
                ["fhir_id", "TEXT", "populated after upload"],
            ],
        )
        + h(3, "patient_pregnancy_snapshot (v8)")
        + table(
            ["Column", "Type"],
            [
                ["patient_id", "TEXT PK"],
                ["high_risk_pregnant_woman", "INTEGER (bool)"],
                ["has_gaps_in_anc", "INTEGER (bool)"],
                ["is_postpartum_window", "INTEGER (bool)"],
                ["is_near_term_anc", "INTEGER (bool)"],
                ["had_delivery_complications", "INTEGER (bool)"],
                ["has_pnc_illness", "INTEGER (bool)"],
            ],
        )
        + h(3, "eval_log (v11)")
        + p(
            "Shadow dataset for AI model evaluation. Written on every completed assessment. "
            "Stores: activated_programmes, symptoms, field_values, cds_alerts, patient_context_json. "
            "upload_status: pending → uploaded."
        )
    )


def page_assessment_cds() -> str:
    return (
        h(1, "Assessment &amp; CDS")
        + h(2, "3-step visit flow")
        + code(
            "Step 1: Triage / Vitals\n"
            "  ├─ Vital signs (BP, pulse, temp, SpO2, weight, height)\n"
            "  └─ Chief complaints (symptom selection from UnifiedSymptomCatalog)\n\n"
            "Step 2: Sectioned Assessment\n"
            "  ├─ Programme sections rendered in priority order (SectionRegistry)\n"
            "  ├─ CDS banners fire as fields are filled\n"
            "  └─ 'Add pathway' CDS actions activate new sections on the fly\n\n"
            "Step 3: Summary & Submit\n"
            "  ├─ CDS alerts review\n"
            "  ├─ Referral decision\n"
            "  └─ Submit → local_assessments (sync_status=pending) → upload queue",
            language="text",
        )
        + h(2, "Section Registry")
        + p("<em>lib/features/visit/composer/section_registry.dart</em>")
        + table(
            ["Section ID", "Programmes", "Priority", "Key fields"],
            [
                ["vitals", "all", "10", "BP, pulse, temp, SpO2"],
                ["symptoms", "all", "20", "UnifiedSymptomCatalog chips"],
                ["imci-u5", "imci", "30", "IMCI danger signs, diarrhoea, fever"],
                ["anc-basic", "anc", "35", "GA weeks, fundal height, foetal HR"],
                ["anc-risk", "anc", "36", "BP, proteinuria, oedema"],
                ["pnc-basic", "pnc", "40", "days postpartum, lochia, breast exam"],
                ["ncd-htn", "ncd", "42", "BP, on BP medication"],
                ["ncd-dm", "ncd", "43", "glucose type, glucose value"],
                ["ncd-findrisc", "ncd", "44", "waist cm, physical activity, diet, prior glucose, family DM"],
                ["tb-screening", "tb", "50", "cough duration, haemoptysis, night sweats"],
                ["epi-vaccines", "epi", "55", "vaccines administered"],
                ["nutrition", "nutrition", "60", "MUAC, oedema grade, feeding"],
                ["family-planning", "familyPlanning", "80", "living children, current FP method"],
                ["cataract-exam", "cataract", "85", "eye disease types, referral"],
                ["eye-care-exam", "eyeCare", "90", "eye test outcome, glasses"],
            ],
        )
        + h(2, "CDS Rules — threshold alerts")
        + p("<em>lib/features/visit/composer/cds_rules.dart</em> — <code>CdsRules.evaluate()</code>")
        + table(
            ["Alert ID", "Condition", "Severity", "Action"],
            [
                ["bp_critical", "systolic ≥ 180 or diastolic ≥ 120", "urgent", "referNow"],
                ["bp_stage2", "systolic ≥ 140 or diastolic ≥ 90", "warning", "addPathway(ncd)"],
                ["glucose_high", "random glucose ≥ 11.1", "urgent", "addPathway(ncd)"],
                ["glucose_fasting_high", "fasting glucose ≥ 7.0", "warning", "addPathway(ncd)"],
                ["low_muac", "MUAC &lt; 115mm", "urgent", "addPathway(nutrition)"],
                ["muac_mam", "MUAC 115–124mm", "warning", "addPathway(nutrition)"],
                ["spo2_low", "SpO2 &lt; 94%", "urgent", "referNow"],
                ["temp_fever", "temp ≥ 38.5°C", "warning", "continueAssessment"],
                ["mini_piers_high", "miniPIERS risk ≥ 25%", "warning", "addPathway(anc)"],
                ["mini_piers_critical", "miniPIERS risk ≥ 50%", "urgent", "referNow"],
            ],
        )
        + h(2, "CDSS Algorithms")
        + p("<em>lib/core/cdss/</em> — six validated clinical algorithms")
        + table(
            ["Algorithm", "Class", "Inputs", "Trigger"],
            [
                ["FINDRISC", "FindriscCalculator", "age, BMI, waist, activity, diet, BP meds, prior glucose, family DM", "score ≥ 12"],
                ["Framingham CVD", "FraminghamCalculator", "age, sex, BMI, SBP, smoking, diabetes, BP meds", "10-yr risk ≥ 10%"],
                ["CUSUM", "CusumCalculator", "BP history ≥ 2 readings", "cumulative sum &gt; 40"],
                ["EWMA", "EwmaCalculator", "BP history ≥ 2 readings", "EWMA &gt; μ₀ + 14.1"],
                ["Linear Slope", "SlopeCalculator", "BP history ≥ 2 readings", "slope &gt; 4 mmHg/visit"],
                ["miniPIERS", "MiniPiersCalculator", "GA weeks, SBP, proteinuria, headache, chest pain", "risk ≥ 25%"],
            ],
        )
        + p("<code>CdssEngine.evaluate()</code> runs all applicable algorithms and returns <code>CdssEngineOutput</code>.")
        + h(2, "Eval log")
        + p(
            "Every completed assessment writes a shadow record to <code>eval_log</code>: "
            "activated programmes, symptoms, field values, CDS alerts, patient context JSON. "
            "Used for AI model evaluation. Upload tracked via <code>upload_status</code>."
        )
    )


def page_api_reference() -> str:
    return (
        h(1, "API Reference")
        + info("All endpoints are on the <code>offline-service</code> at port 80 (via nginx). Auth: <code>Authorization: Bearer &lt;jwt&gt;</code>.")
        + h(2, "Auth")
        + table(
            ["Method", "Path", "Description", "Body"],
            [
                ["POST", "/offline-service/offline-sync/login", "Login. Returns JWT in Authorization response header.", "multipart: username, password"],
            ],
        )
        + h(2, "Sync — download")
        + table(
            ["Method", "Path", "Description"],
            [
                ["GET", "/offline-service/offline-sync/household-list", "All households in SK catchment"],
                ["GET", "/offline-service/offline-sync/member-list", "All members"],
                ["GET", "/offline-service/offline-sync/patient-list", "All enrolled patients"],
                ["GET", "/offline-service/offline-sync/member-assessment-history", "Assessment history per member"],
                ["GET", "/offline-service/offline-sync/follow-up-list", "Scheduled follow-ups"],
                ["GET", "/offline-service/offline-sync/immunisation-list", "Immunisation schedule"],
                ["GET", "/offline-service/offline-sync/referral-list", "Active referrals"],
            ],
        )
        + h(2, "Sync — upload")
        + table(
            ["Method", "Path", "Description", "Body"],
            [
                ["POST", "/offline-service/offline-sync/assessment-upload", "Upload completed assessment", "JSON: assessment payload"],
            ],
        )
        + h(2, "Notes")
        + "<ul>"
        + "<li>All timestamps are epoch milliseconds (INTEGER in SQLite, long in Java).</li>"
        + "<li>Warm sync uses <code>?updatedAt=&lt;last_sync_epoch&gt;</code> query param on list endpoints.</li>"
        + "<li>JWT expiry: re-login on 401 response; token stored in flutter_secure_storage.</li>"
        + "<li>Never invent endpoint paths — verify against the Java offline-service controllers and <code>lib/core/api/endpoints.dart</code>.</li>"
        + "</ul>"
    )


def page_changelog() -> str:
    try:
        raw = subprocess.check_output(
            ["git", "log", "--oneline", "-50", "--format=%H|%h|%s|%ai|%an"],
            text=True,
        ).strip().split("\n")
    except subprocess.CalledProcessError:
        raw = []

    rows = []
    for line in raw:
        if not line:
            continue
        parts = line.split("|", 4)
        if len(parts) < 5:
            continue
        full_hash, short_hash, msg, date, author = parts
        link = f'<a href="https://github.com/Medtronic-LABS/uhis_lf_mobile/commit/{full_hash}"><code>{short_hash}</code></a>'
        rows.append([link, msg, date[:10], author])

    return (
        h(1, "Changelog")
        + info(f"Auto-generated from git history. Last 50 commits. Updated: {TODAY}.")
        + (
            table(["Commit", "Message", "Date", "Author"], rows)
            if rows
            else p("No git history available.")
        )
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
PAGES = [
    ("UHIS Leapfrog Mobile", page_home),
    ("Developer Setup Guide", page_developer_setup),
    ("Architecture Overview", page_architecture),
    ("Screens & Navigation", page_screens),
    ("Offline Sync Model", page_offline_sync),
    ("Database Schema", page_database),
    ("Assessment & CDS", page_assessment_cds),
    ("API Reference", page_api_reference),
    ("Changelog", page_changelog),
]

if __name__ == "__main__":
    print(f"Publishing {len(PAGES)} pages to {BASE_URL} (space: {SPACE}, parent: {PARENT_ID})")
    errors = []
    for title, builder in PAGES:
        try:
            upsert(title, builder())
        except Exception as exc:
            print(f"  ✗ error    → {title}: {exc}", file=sys.stderr)
            errors.append(title)
    if errors:
        print(f"\nFailed pages: {errors}", file=sys.stderr)
        sys.exit(1)
    print(f"\nDone — {len(PAGES)} pages published.")
