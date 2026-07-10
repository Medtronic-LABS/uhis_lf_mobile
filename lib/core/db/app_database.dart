import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import '../debug/console_log.dart';
import 'key_store.dart';

/// Local SQLite store for the offline cache (households, members, patients)
/// plus per-entity sync bookkeeping. Schema v2 added the AI Worklist tables
/// (programmes, follow_ups, immunisations, assessments) and the risk columns
/// on `patients`. Schema v3 adds the Referral SLA tables (referrals,
/// referral_status_events, notification_log) — see
/// `leapfrog-setup/designs/referral-sla-engine.md`.
///
/// The database is encrypted at rest with SQLCipher using a per-device key
/// from Android EncryptedSharedPreferences (backed by the Android Keystore).
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int schemaVersion = 24;
  static const String _fileName = 'uhis_offline.db';

  static const String tableHouseholds = 'households';
  static const String tableMembers = 'members';
  static const String tablePatients = 'patients';
  static const String tableSyncMeta = 'sync_meta';
  static const String tablePatientProgrammes = 'patient_programmes';
  static const String tableFollowUps = 'follow_ups';
  static const String tableImmunisations = 'immunisations';
  static const String tableAssessments = 'assessments';
  static const String tableReferrals = 'referrals';
  static const String tableReferralStatusEvents = 'referral_status_events';
  static const String tableNotificationLog = 'notification_log';
  static const String tableEncounters = 'encounters';
  static const String tableLocalAssessments = 'local_assessments';
  static const String tablePregnancySnapshot = 'patient_pregnancy_snapshot';
  static const String tableTreatmentPresence = 'patient_treatment_presence';
  static const String tableAssessmentDraft = 'assessment_draft';
  static const String tableAiSuggestions = 'ai_suggestions';
  static const String tableEvalLog = 'eval_log';
  static const String tableAiResponseCache = 'ai_response_cache';
  static const String tableCoachingModules = 'coaching_modules';
  static const String tableCoachingProgress = 'coaching_progress';

  /// Opens (creating if needed) the on-device database, encrypted with
  /// a per-device key stored in Android EncryptedSharedPreferences.
  ///
  /// If a stale plain-SQLite file is found (e.g. from a pre-encryption build),
  /// SQLCipher raises SQLITE_NOTADB (code 26). We delete the corrupt/stale file
  /// and recreate a fresh encrypted DB — data is recovered via the next sync.
  static Future<AppDatabase> open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _fileName);
    final key = await KeyStore.getKey();
    try {
      final db = await sqlcipher.openDatabase(
        path,
        password: key,
        version: schemaVersion,
        onCreate: createSchema,
        onUpgrade: _onUpgrade,
      );
      return AppDatabase._(db);
    } on DatabaseException catch (e) {
      // SQLITE_NOTADB (26) or SQLITE_CANTOPEN (14) — stale unencrypted file
      // or corrupted DB. Wipe and recreate; data re-syncs from server.
      if (e.isOpenFailedError() ||
          e.toString().contains('not a database') ||
          e.toString().contains('open_failed')) {
        final file = File(path);
        if (await file.exists()) await file.delete();
        final db = await sqlcipher.openDatabase(
          path,
          password: key,
          version: schemaVersion,
          onCreate: createSchema,
          onUpgrade: _onUpgrade,
        );
        return AppDatabase._(db);
      }
      rethrow;
    }
  }

  /// Opens an in-memory database — used for web e2e testing where the file
  /// system is unavailable. Data does not persist across page reloads.
  static Future<AppDatabase> openInMemory() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: schemaVersion,
      onCreate: createSchema,
    );
    return AppDatabase._(db);
  }

  /// Wraps an already-open [Database] — used by tests with an in-memory FFI db.
  AppDatabase.forTesting(this.db);

  /// Creates the schema. Exposed (not private) so tests can build an in-memory
  /// database with the same DDL the app uses.
  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableHouseholds (
        id TEXT PRIMARY KEY,
        fhir_id TEXT,
        household_no TEXT,
        name TEXT,
        village TEXT,
        village_id TEXT,
        member_count INTEGER,
        landmark TEXT,
        head_phone_number TEXT,
        head_phone_number_category TEXT,
        latitude REAL,
        longitude REAL,
        is_owned_an_improved_latrine INTEGER DEFAULT 0,
        is_owned_hand_washing_facility INTEGER DEFAULT 0,
        is_owned_a_treated_bed_net INTEGER DEFAULT 0,
        bed_net_count INTEGER,
        version TEXT,
        last_updated TEXT,
        created_at INTEGER,
        updated_at INTEGER,
        sync_status TEXT DEFAULT 'Success',
        raw_json TEXT
      )''');
    await db.execute('''
      CREATE TABLE $tableMembers (
        id TEXT PRIMARY KEY,
        fhir_id TEXT,
        household_id TEXT,
        household_reference_id TEXT,
        reference_id TEXT,
        name TEXT,
        gender TEXT,
        dob TEXT,
        phone TEXT,
        phone_number_category TEXT,
        national_id TEXT,
        patient_id TEXT,
        village_id TEXT,
        village_name TEXT,
        sub_village_id TEXT,
        sub_village_name TEXT,
        shasthya_shebika_id TEXT,
        is_active INTEGER,
        is_household_head INTEGER,
        is_pregnant INTEGER,
        relation TEXT,
        initial TEXT,
        signature TEXT,
        local_signature_file TEXT,
        mother_patient_id TEXT,
        mother_reference_id TEXT,
        marital_status TEXT,
        disability TEXT,
        guardian_id TEXT,
        guardian_fhir_id TEXT,
        latitude REAL,
        longitude REAL,
        id_type TEXT,
        version TEXT,
        last_updated TEXT,
        created_at INTEGER,
        updated_at INTEGER,
        sync_status TEXT DEFAULT 'Success',
        raw_json TEXT
      )''');
    await db.execute('''
      CREATE TABLE $tablePatients (
        id TEXT PRIMARY KEY,
        patient_id TEXT,
        name TEXT,
        gender TEXT,
        dob TEXT,
        phone TEXT,
        national_id TEXT,
        household_id TEXT,
        village_id TEXT,
        village_name TEXT,
        is_active INTEGER,
        updated_at INTEGER,
        raw_json TEXT,
        age INTEGER,
        risk_score INTEGER,
        risk_band TEXT,
        risk_modifier TEXT,
        risk_reasons TEXT,
        risk_hint_level TEXT,
        risk_hint_color TEXT,
        red_flag INTEGER,
        last_visit_at INTEGER,
        next_due_at INTEGER,
        missed_visit_count INTEGER
      )''');
    await db.execute('''
      CREATE TABLE $tableSyncMeta (
        entity TEXT PRIMARY KEY,
        last_sync_time INTEGER,
        last_full_sync_at INTEGER
      )''');
    await db.execute('''
      CREATE TABLE $tablePatientProgrammes (
        patient_id TEXT NOT NULL,
        programme TEXT NOT NULL,
        PRIMARY KEY (patient_id, programme)
      )''');
    await db.execute('''
      CREATE TABLE $tableFollowUps (
        id TEXT PRIMARY KEY,
        patient_id TEXT,
        kind TEXT,
        due_at INTEGER,
        completed_at INTEGER,
        attempts INTEGER,
        unsuccessful_attempts INTEGER,
        type TEXT,
        referred_site_id TEXT,
        is_lost INTEGER,
        raw_json TEXT
      )''');
    await db.execute('''
      CREATE TABLE $tableImmunisations (
        id TEXT PRIMARY KEY,
        patient_id TEXT,
        vaccine_code TEXT,
        due_at INTEGER,
        given_at INTEGER,
        raw_json TEXT
      )''');
    await db.execute('''
      CREATE TABLE $tableAssessments (
        id TEXT PRIMARY KEY,
        patient_id TEXT,
        kind TEXT,
        occurred_at INTEGER,
        raw_json TEXT
      )''');
    await db.execute('''
      CREATE TABLE $tableReferrals (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        household_id TEXT,
        village_id TEXT,
        sla_tier TEXT NOT NULL,
        diagnosis_code TEXT,
        diagnosis_label TEXT,
        state TEXT NOT NULL,
        priority_score INTEGER,
        priority_level TEXT,
        priority_drivers TEXT,
        rationale_json TEXT,
        due_arrival_at INTEGER,
        due_treatment_at INTEGER,
        breached_since INTEGER,
        escalation_level INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        closed_at INTEGER,
        raw_json TEXT
      )''');
    await db.execute('''
      CREATE TABLE $tableReferralStatusEvents (
        id TEXT PRIMARY KEY,
        referral_id TEXT NOT NULL,
        from_state TEXT,
        to_state TEXT NOT NULL,
        occurred_at INTEGER NOT NULL,
        actor TEXT,
        reason TEXT,
        raw_json TEXT
      )''');
    await db.execute('''
      CREATE TABLE $tableNotificationLog (
        id TEXT PRIMARY KEY,
        referral_id TEXT NOT NULL,
        channel TEXT NOT NULL,
        fired_at INTEGER NOT NULL,
        next_repeat_at INTEGER,
        payload_json TEXT
      )''');

    await db.execute(
        'CREATE INDEX idx_members_hh ON $tableMembers(household_id)');
    await db.execute('CREATE INDEX idx_members_name ON $tableMembers(name)');
    await db.execute('CREATE INDEX idx_patients_name ON $tablePatients(name)');
    await db.execute(
        'CREATE INDEX idx_households_name ON $tableHouseholds(name)');
    await db.execute(
        'CREATE INDEX idx_patients_risk_score ON $tablePatients(risk_score DESC)');
    await db.execute(
        'CREATE INDEX idx_patients_due ON $tablePatients(next_due_at)');
    await db.execute(
        'CREATE INDEX idx_pp_patient ON $tablePatientProgrammes(patient_id)');
    await db.execute(
        'CREATE INDEX idx_pp_programme ON $tablePatientProgrammes(programme)');
    await db.execute(
        'CREATE INDEX idx_fu_patient ON $tableFollowUps(patient_id, kind)');
    await db.execute(
        'CREATE INDEX idx_fu_due ON $tableFollowUps(due_at)');
    await db.execute(
        'CREATE INDEX idx_im_patient ON $tableImmunisations(patient_id)');
    await db.execute(
        'CREATE INDEX idx_as_patient ON $tableAssessments(patient_id, occurred_at)');
    await db.execute(
        'CREATE INDEX idx_ref_priority ON $tableReferrals(priority_score DESC)');
    await db.execute(
        'CREATE INDEX idx_ref_breached ON $tableReferrals(breached_since)');
    await db.execute(
        'CREATE INDEX idx_ref_state ON $tableReferrals(state)');
    await db.execute(
        'CREATE INDEX idx_ref_patient ON $tableReferrals(patient_id)');
    await db.execute(
        'CREATE INDEX idx_ref_due_arr ON $tableReferrals(due_arrival_at)');
    await db.execute(
        'CREATE INDEX idx_rse_ref ON $tableReferralStatusEvents(referral_id, occurred_at)');
    await db.execute(
        'CREATE INDEX idx_nl_ref ON $tableNotificationLog(referral_id)');
    await db.execute(
        'CREATE INDEX idx_nl_repeat ON $tableNotificationLog(next_repeat_at)');

    // v4 — Encounters table for offline-first visit capture
    await db.execute('''
      CREATE TABLE $tableEncounters (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        programme TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        completed_at INTEGER,
        status TEXT NOT NULL DEFAULT 'draft',
        sync_status TEXT NOT NULL DEFAULT 'pending',
        server_visit_id TEXT,
        triage_json TEXT,
        vitals_json TEXT,
        assessment_json TEXT
      )''');
    await db.execute(
        'CREATE INDEX idx_enc_patient ON $tableEncounters(patient_id)');
    await db.execute(
        'CREATE INDEX idx_enc_status ON $tableEncounters(status)');
    await db.execute(
        'CREATE INDEX idx_enc_sync ON $tableEncounters(sync_status)');
    await db.execute(
        'CREATE INDEX idx_enc_started ON $tableEncounters(started_at DESC)');

    // v5 — Local assessments table for offline-first assessment capture
    await db.execute('''
      CREATE TABLE $tableLocalAssessments (
        id TEXT PRIMARY KEY,
        household_member_local_id INTEGER NOT NULL,
        member_id TEXT,
        household_id TEXT,
        patient_id TEXT,
        village_id TEXT,
        assessment_type TEXT NOT NULL,
        assessment_details TEXT NOT NULL,
        other_details TEXT,
        is_referred INTEGER DEFAULT 0,
        referral_status TEXT,
        referred_reasons TEXT,
        follow_up_id INTEGER,
        pregnancy_episode_id TEXT,
        latitude REAL DEFAULT 0.0,
        longitude REAL DEFAULT 0.0,
        sync_status TEXT DEFAULT 'pending',
        fhir_id TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )''');
    await db.execute(
        'CREATE INDEX idx_local_assessments_patient ON $tableLocalAssessments(patient_id)');
    await db.execute(
        'CREATE INDEX idx_local_assessments_sync ON $tableLocalAssessments(sync_status)');

    // v8 — Tiered Mission Dashboard side tables (spec
    // leapfrog-setup/designs/dashboard-prioritization-impl.md).
    await db.execute('''
      CREATE TABLE $tablePregnancySnapshot (
        patient_id TEXT PRIMARY KEY,
        high_risk_pregnant_woman INTEGER NOT NULL DEFAULT 0,
        has_gaps_in_anc INTEGER NOT NULL DEFAULT 0,
        is_postpartum_window INTEGER NOT NULL DEFAULT 0,
        is_near_term_anc INTEGER NOT NULL DEFAULT 0,
        had_delivery_complications INTEGER NOT NULL DEFAULT 0,
        has_pnc_illness INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER,
        edd_date INTEGER,
        lmp_date INTEGER
      )''');
    await db.execute('''
      CREATE TABLE $tableTreatmentPresence (
        patient_id TEXT PRIMARY KEY,
        updated_at INTEGER
      )''');

    // v9 — Assessment draft table for offline-first sectioned assessment flow.
    await db.execute('''
      CREATE TABLE $tableAssessmentDraft (
        encounter_id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        member_id TEXT,
        activated_programmes TEXT NOT NULL,
        skipped_pathways TEXT,
        field_values TEXT NOT NULL,
        section_status TEXT NOT NULL,
        created_at INTEGER,
        updated_at INTEGER
      )''');
    await db.execute(
        'CREATE INDEX idx_draft_patient ON $tableAssessmentDraft(patient_id)');
    await db.execute(
        'CREATE INDEX idx_draft_updated ON $tableAssessmentDraft(updated_at DESC)');

    // v10 — AI suggestions cache for fire-and-forget pathway suggestions.
    await db.execute('''
      CREATE TABLE $tableAiSuggestions (
        member_id TEXT PRIMARY KEY,
        suggestions_json TEXT NOT NULL,
        fetched_at INTEGER NOT NULL
      )''');

    // v11 — Phase 6 eval-dataset shadow log.
    await db.execute('''
      CREATE TABLE $tableEvalLog (
        id TEXT PRIMARY KEY,
        encounter_id TEXT NOT NULL,
        patient_id TEXT NOT NULL,
        member_id TEXT NOT NULL,
        captured_at INTEGER NOT NULL,
        activated_programmes TEXT NOT NULL,
        symptoms TEXT NOT NULL,
        field_values TEXT NOT NULL,
        cds_alerts TEXT NOT NULL,
        patient_context_json TEXT NOT NULL,
        upload_status TEXT NOT NULL DEFAULT 'pending',
        uploaded_at INTEGER,
        fhir_doc_ref_id TEXT
      )''');
    await db.execute(
        'CREATE INDEX idx_eval_log_patient ON $tableEvalLog(patient_id)');
    await db.execute(
        'CREATE INDEX idx_eval_log_upload ON $tableEvalLog(upload_status)');
    await db.execute(
        'CREATE INDEX idx_eval_log_captured ON $tableEvalLog(captured_at DESC)');

    // v15 — AI response cache. Stores the most recent payload returned by an
    // AI service (briefing, programme recommendation, etc) so re-opening a
    // visit or revisiting a step does not re-hit the API. Keyed by a
    // caller-controlled cache_key (typically `{kind}:{visitId|patientId}`)
    // plus a content_hash that the caller bumps when the input changes.
    await db.execute('''
      CREATE TABLE $tableAiResponseCache (
        cache_key TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL
      )''');
    await db.execute(
        'CREATE INDEX idx_ai_cache_kind ON $tableAiResponseCache(kind)');
    await db.execute(
        'CREATE INDEX idx_ai_cache_expires ON $tableAiResponseCache(expires_at)');

    // v16 — Micro-coaching module cache + progress tables.
    await db.execute('''
      CREATE TABLE $tableCoachingModules (
        id TEXT PRIMARY KEY,
        domain TEXT NOT NULL,
        title_en TEXT NOT NULL,
        title_bn TEXT NOT NULL,
        estimated_minutes INTEGER NOT NULL DEFAULT 5,
        raw_json TEXT NOT NULL,
        priority_today INTEGER NOT NULL DEFAULT 0,
        synced_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE $tableCoachingProgress (
        module_id TEXT PRIMARY KEY,
        passed INTEGER NOT NULL DEFAULT 0,
        quiz_score REAL NOT NULL DEFAULT 0.0,
        last_card_viewed INTEGER NOT NULL DEFAULT -1,
        updated_at INTEGER NOT NULL
      )''');
  }

  static Future<void> _onUpgrade(Database db, int from, int to) async {
    if (from < 2) {
      // Add risk + programme columns to the existing patients row.
      // SQLite has no IF NOT EXISTS for ADD COLUMN, so each ALTER is wrapped
      // in a tolerant try/catch — re-running the migration on a partially
      // upgraded db is a no-op.
      Future<void> addCol(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* column already present */}
      }
      await addCol('ALTER TABLE $tablePatients ADD COLUMN age INTEGER');
      await addCol('ALTER TABLE $tablePatients ADD COLUMN risk_score INTEGER');
      await addCol('ALTER TABLE $tablePatients ADD COLUMN risk_band TEXT');
      await addCol('ALTER TABLE $tablePatients ADD COLUMN risk_reasons TEXT');
      await addCol(
          'ALTER TABLE $tablePatients ADD COLUMN risk_hint_level TEXT');
      await addCol(
          'ALTER TABLE $tablePatients ADD COLUMN risk_hint_color TEXT');
      await addCol('ALTER TABLE $tablePatients ADD COLUMN red_flag INTEGER');
      await addCol(
          'ALTER TABLE $tablePatients ADD COLUMN last_visit_at INTEGER');
      await addCol(
          'ALTER TABLE $tablePatients ADD COLUMN next_due_at INTEGER');
      await addCol(
          'ALTER TABLE $tablePatients ADD COLUMN missed_visit_count INTEGER');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tablePatientProgrammes (
          patient_id TEXT NOT NULL,
          programme TEXT NOT NULL,
          PRIMARY KEY (patient_id, programme)
        )''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableFollowUps (
          id TEXT PRIMARY KEY,
          patient_id TEXT,
          kind TEXT,
          due_at INTEGER,
          completed_at INTEGER,
          attempts INTEGER,
          is_lost INTEGER,
          raw_json TEXT
        )''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableImmunisations (
          id TEXT PRIMARY KEY,
          patient_id TEXT,
          vaccine_code TEXT,
          due_at INTEGER,
          given_at INTEGER,
          raw_json TEXT
        )''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableAssessments (
          id TEXT PRIMARY KEY,
          patient_id TEXT,
          kind TEXT,
          occurred_at INTEGER,
          raw_json TEXT
        )''');

      Future<void> addIdx(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* index already present */}
      }
      await addIdx(
          'CREATE INDEX IF NOT EXISTS idx_patients_risk_score ON $tablePatients(risk_score DESC)');
      await addIdx(
          'CREATE INDEX IF NOT EXISTS idx_patients_due ON $tablePatients(next_due_at)');
      await addIdx(
          'CREATE INDEX IF NOT EXISTS idx_pp_patient ON $tablePatientProgrammes(patient_id)');
      await addIdx(
          'CREATE INDEX IF NOT EXISTS idx_pp_programme ON $tablePatientProgrammes(programme)');
      await addIdx(
          'CREATE INDEX IF NOT EXISTS idx_fu_patient ON $tableFollowUps(patient_id, kind)');
      await addIdx(
          'CREATE INDEX IF NOT EXISTS idx_fu_due ON $tableFollowUps(due_at)');
      await addIdx(
          'CREATE INDEX IF NOT EXISTS idx_im_patient ON $tableImmunisations(patient_id)');
      await addIdx(
          'CREATE INDEX IF NOT EXISTS idx_as_patient ON $tableAssessments(patient_id, occurred_at)');
    }
    if (from < 3) {
      // v3 — Referral SLA tables. Additive only, no drops. Tolerant to
      // partial-upgrade re-runs (mirrors the v2 pattern above).
      Future<void> addTbl(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* table already present */}
      }
      Future<void> addIdx3(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* index already present */}
      }
      await addTbl('''
        CREATE TABLE IF NOT EXISTS $tableReferrals (
          id TEXT PRIMARY KEY,
          patient_id TEXT NOT NULL,
          household_id TEXT,
          village_id TEXT,
          sla_tier TEXT NOT NULL,
          diagnosis_code TEXT,
          diagnosis_label TEXT,
          state TEXT NOT NULL,
          priority_score INTEGER,
          priority_level TEXT,
          priority_drivers TEXT,
          rationale_json TEXT,
          due_arrival_at INTEGER,
          due_treatment_at INTEGER,
          breached_since INTEGER,
          escalation_level INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          closed_at INTEGER,
          raw_json TEXT
        )''');
      await addTbl('''
        CREATE TABLE IF NOT EXISTS $tableReferralStatusEvents (
          id TEXT PRIMARY KEY,
          referral_id TEXT NOT NULL,
          from_state TEXT,
          to_state TEXT NOT NULL,
          occurred_at INTEGER NOT NULL,
          actor TEXT,
          reason TEXT,
          raw_json TEXT
        )''');
      await addTbl('''
        CREATE TABLE IF NOT EXISTS $tableNotificationLog (
          id TEXT PRIMARY KEY,
          referral_id TEXT NOT NULL,
          channel TEXT NOT NULL,
          fired_at INTEGER NOT NULL,
          next_repeat_at INTEGER,
          payload_json TEXT
        )''');
      await addIdx3(
          'CREATE INDEX IF NOT EXISTS idx_ref_priority ON $tableReferrals(priority_score DESC)');
      await addIdx3(
          'CREATE INDEX IF NOT EXISTS idx_ref_breached ON $tableReferrals(breached_since)');
      await addIdx3(
          'CREATE INDEX IF NOT EXISTS idx_ref_state ON $tableReferrals(state)');
      await addIdx3(
          'CREATE INDEX IF NOT EXISTS idx_ref_patient ON $tableReferrals(patient_id)');
      await addIdx3(
          'CREATE INDEX IF NOT EXISTS idx_ref_due_arr ON $tableReferrals(due_arrival_at)');
      await addIdx3(
          'CREATE INDEX IF NOT EXISTS idx_rse_ref ON $tableReferralStatusEvents(referral_id, occurred_at)');
      await addIdx3(
          'CREATE INDEX IF NOT EXISTS idx_nl_ref ON $tableNotificationLog(referral_id)');
      await addIdx3(
          'CREATE INDEX IF NOT EXISTS idx_nl_repeat ON $tableNotificationLog(next_repeat_at)');
    }
    if (from < 4) {
      // v4 — Encounters table for offline-first visit capture.
      Future<void> addTbl4(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* table already present */}
      }
      Future<void> addIdx4(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* index already present */}
      }
      await addTbl4('''
        CREATE TABLE IF NOT EXISTS $tableEncounters (
          id TEXT PRIMARY KEY,
          patient_id TEXT NOT NULL,
          programme TEXT NOT NULL,
          started_at INTEGER NOT NULL,
          completed_at INTEGER,
          status TEXT NOT NULL DEFAULT 'draft',
          sync_status TEXT NOT NULL DEFAULT 'pending',
          server_visit_id TEXT,
          triage_json TEXT,
          vitals_json TEXT,
          assessment_json TEXT
        )''');
      await addIdx4(
          'CREATE INDEX IF NOT EXISTS idx_enc_patient ON $tableEncounters(patient_id)');
      await addIdx4(
          'CREATE INDEX IF NOT EXISTS idx_enc_status ON $tableEncounters(status)');
      await addIdx4(
          'CREATE INDEX IF NOT EXISTS idx_enc_sync ON $tableEncounters(sync_status)');
      await addIdx4(
          'CREATE INDEX IF NOT EXISTS idx_enc_started ON $tableEncounters(started_at DESC)');
    }
    if (from < 5) {
      // v5 — Local assessments table for offline-first assessment capture.
      Future<void> addTbl5(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* table already present */}
      }
      Future<void> addIdx5(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* index already present */}
      }
      await addTbl5('''
        CREATE TABLE IF NOT EXISTS $tableLocalAssessments (
          id TEXT PRIMARY KEY,
          household_member_local_id INTEGER NOT NULL,
          member_id TEXT,
          household_id TEXT,
          patient_id TEXT,
          village_id TEXT,
          assessment_type TEXT NOT NULL,
          assessment_details TEXT NOT NULL,
          other_details TEXT,
          is_referred INTEGER DEFAULT 0,
          referral_status TEXT,
          referred_reasons TEXT,
          follow_up_id INTEGER,
          latitude REAL DEFAULT 0.0,
          longitude REAL DEFAULT 0.0,
          sync_status TEXT DEFAULT 'pending',
          fhir_id TEXT,
          created_at INTEGER,
          updated_at INTEGER
        )''');
      await addIdx5(
          'CREATE INDEX IF NOT EXISTS idx_local_assessments_patient ON $tableLocalAssessments(patient_id)');
      await addIdx5(
          'CREATE INDEX IF NOT EXISTS idx_local_assessments_sync ON $tableLocalAssessments(sync_status)');
    }
    if (from < 6) {
      // v6 — Add household head, pregnant, relation columns to members table.
      Future<void> addCol6(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* column already present */}
      }
      await addCol6('ALTER TABLE $tableMembers ADD COLUMN is_household_head INTEGER');
      await addCol6('ALTER TABLE $tableMembers ADD COLUMN is_pregnant INTEGER');
      await addCol6('ALTER TABLE $tableMembers ADD COLUMN relation TEXT');
    }
    if (from < 7) {
      // v7 — Add extended fields to households and members tables to match
      // Android uhis-dev HouseholdEntity and HouseholdMemberEntity.
      Future<void> addCol7(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* column already present */}
      }
      // Households extended fields
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN fhir_id TEXT');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN landmark TEXT');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN head_phone_number TEXT');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN head_phone_number_category TEXT');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN latitude REAL');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN longitude REAL');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN is_owned_an_improved_latrine INTEGER DEFAULT 0');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN is_owned_hand_washing_facility INTEGER DEFAULT 0');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN is_owned_a_treated_bed_net INTEGER DEFAULT 0');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN bed_net_count INTEGER');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN version TEXT');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN last_updated TEXT');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN created_at INTEGER');
      await addCol7('ALTER TABLE $tableHouseholds ADD COLUMN sync_status TEXT DEFAULT "Success"');
      // Members extended fields
      await addCol7('ALTER TABLE $tableMembers ADD COLUMN fhir_id TEXT');
      await addCol7('ALTER TABLE $tableMembers ADD COLUMN household_reference_id TEXT');
      await addCol7('ALTER TABLE $tableMembers ADD COLUMN phone_number_category TEXT');
      await addCol7('ALTER TABLE $tableMembers ADD COLUMN initial TEXT');
      await addCol7('ALTER TABLE $tableMembers ADD COLUMN signature TEXT');
      await addCol7('ALTER TABLE $tableMembers ADD COLUMN local_signature_file TEXT');
      await addCol7('ALTER TABLE $tableMembers ADD COLUMN mother_patient_id TEXT');
      await addCol7('ALTER TABLE $tableMembers ADD COLUMN mother_reference_id TEXT');
      await addCol7('ALTER TABLE $tableMembers ADD COLUMN version TEXT');
      await addCol7('ALTER TABLE $tableMembers ADD COLUMN last_updated TEXT');
      await addCol7('ALTER TABLE $tableMembers ADD COLUMN created_at INTEGER');
      await addCol7('ALTER TABLE $tableMembers ADD COLUMN sync_status TEXT DEFAULT "Success"');
    }
    if (from < 8) {
      // v8 — Tiered Mission Dashboard side tables. Additive only.
      Future<void> addCol8(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* column already present */}
      }
      Future<void> addTbl8(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* table already present */}
      }
      await addCol8(
          'ALTER TABLE $tableFollowUps ADD COLUMN unsuccessful_attempts INTEGER');
      await addCol8(
          'ALTER TABLE $tableFollowUps ADD COLUMN type TEXT');
      await addCol8(
          'ALTER TABLE $tableFollowUps ADD COLUMN referred_site_id TEXT');
      await addTbl8('''
        CREATE TABLE IF NOT EXISTS $tablePregnancySnapshot (
          patient_id TEXT PRIMARY KEY,
          high_risk_pregnant_woman INTEGER NOT NULL DEFAULT 0,
          has_gaps_in_anc INTEGER NOT NULL DEFAULT 0,
          is_postpartum_window INTEGER NOT NULL DEFAULT 0,
          is_near_term_anc INTEGER NOT NULL DEFAULT 0,
          had_delivery_complications INTEGER NOT NULL DEFAULT 0,
          has_pnc_illness INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER,
          edd_date INTEGER,
          lmp_date INTEGER
        )''');
      await addTbl8('''
        CREATE TABLE IF NOT EXISTS $tableTreatmentPresence (
          patient_id TEXT PRIMARY KEY,
          updated_at INTEGER
        )''');
    }
    if (from < 9) {
      // v9 — Assessment draft table for the Phase 2 sectioned assessment flow.
      Future<void> addTbl9(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* table already present */}
      }
      Future<void> addIdx9(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* index already present */}
      }
      await addTbl9('''
        CREATE TABLE IF NOT EXISTS $tableAssessmentDraft (
          encounter_id TEXT PRIMARY KEY,
          patient_id TEXT NOT NULL,
          member_id TEXT,
          activated_programmes TEXT NOT NULL,
          skipped_pathways TEXT,
          field_values TEXT NOT NULL,
          section_status TEXT NOT NULL,
          created_at INTEGER,
          updated_at INTEGER
        )''');
      await addIdx9(
          'CREATE INDEX IF NOT EXISTS idx_draft_patient ON $tableAssessmentDraft(patient_id)');
      await addIdx9(
          'CREATE INDEX IF NOT EXISTS idx_draft_updated ON $tableAssessmentDraft(updated_at DESC)');
    }
    if (from < 10) {
      // v10 — AI suggestions cache table. Additive only.
      Future<void> addTbl10(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* table already present */}
      }
      await addTbl10('''
        CREATE TABLE IF NOT EXISTS $tableAiSuggestions (
          member_id TEXT PRIMARY KEY,
          suggestions_json TEXT NOT NULL,
          fetched_at INTEGER NOT NULL
        )''');
    }
    if (from < 11) {
      // v11 — Phase 6 eval-dataset shadow log. Additive only.
      Future<void> addTbl11(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* table already present */}
      }
      Future<void> addIdx11(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* index already present */}
      }
      await addTbl11('''
        CREATE TABLE IF NOT EXISTS $tableEvalLog (
          id TEXT PRIMARY KEY,
          encounter_id TEXT NOT NULL,
          patient_id TEXT NOT NULL,
          member_id TEXT NOT NULL,
          captured_at INTEGER NOT NULL,
          activated_programmes TEXT NOT NULL,
          symptoms TEXT NOT NULL,
          field_values TEXT NOT NULL,
          cds_alerts TEXT NOT NULL,
          patient_context_json TEXT NOT NULL,
          upload_status TEXT NOT NULL DEFAULT 'pending',
          uploaded_at INTEGER,
          fhir_doc_ref_id TEXT
        )''');
      await addIdx11(
          'CREATE INDEX IF NOT EXISTS idx_eval_log_patient ON $tableEvalLog(patient_id)');
      await addIdx11(
          'CREATE INDEX IF NOT EXISTS idx_eval_log_upload ON $tableEvalLog(upload_status)');
      await addIdx11(
          'CREATE INDEX IF NOT EXISTS idx_eval_log_captured ON $tableEvalLog(captured_at DESC)');
    }
    if (from < 12) {
      // v12 — Add village name, sub-village, and Shasthya Shebika columns to
      // members table to enable SS / village / sub-village filter UI.
      Future<void> addCol12(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* column already present */}
      }
      await addCol12('ALTER TABLE $tableMembers ADD COLUMN village_name TEXT');
      await addCol12('ALTER TABLE $tableMembers ADD COLUMN sub_village_id TEXT');
      await addCol12('ALTER TABLE $tableMembers ADD COLUMN sub_village_name TEXT');
      await addCol12(
          'ALTER TABLE $tableMembers ADD COLUMN shasthya_shebika_id TEXT');
    }
    if (from < 13) {
      // v13 — Add village_name to patients table so the sub-village text
      // name (e.g. "NAMATARI-00") stored during member sync is available
      // for display without a cross-namespace ID lookup via UserHierarchyService.
      Future<void> addCol13(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* column already present */}
      }
      await addCol13(
          'ALTER TABLE $tablePatients ADD COLUMN village_name TEXT');
    }
    if (from < 14) {
      // v14 — Spec §2.8 band+modifier risk model. risk_band column repurposed
      // to carry `band1`/`band2`/`band3`/`band4`; risk_modifier added for the
      // `a`/`b`/`none` letter modifier. risk_score column retained as the
      // numeric sort rank (sortRankFor(band, modifier)) — DESC ORDER BY still
      // yields the spec sort sequence 1a → 1b → 1 → 2a → 2b → 2 → 3a → 3b → 3 → 4.
      Future<void> addCol14(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* column already present */}
      }
      await addCol14(
          'ALTER TABLE $tablePatients ADD COLUMN risk_modifier TEXT');
      // Stale rows: clear the legacy 0–100 score + old wire tags so the
      // first post-upgrade recompute pass fills them with the new shape.
      await db.execute(
          'UPDATE $tablePatients SET risk_score = NULL, risk_band = NULL, risk_modifier = NULL');
    }
    if (from < 15) {
      // v15 — AI response cache for briefing + programme-recommendation
      // (and future AI surfaces). Keyed by `{kind}:{scopeId}` with a content
      // hash so cache invalidates when the input changes (e.g. SK edits the
      // symptom set before re-entering Step 2).
      Future<void> addTbl15(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* table already present */}
      }
      Future<void> addIdx15(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* index already present */}
      }
      await addTbl15('''
        CREATE TABLE IF NOT EXISTS $tableAiResponseCache (
          cache_key TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          content_hash TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          expires_at INTEGER NOT NULL
        )''');
      await addIdx15(
          'CREATE INDEX IF NOT EXISTS idx_ai_cache_kind ON $tableAiResponseCache(kind)');
      await addIdx15(
          'CREATE INDEX IF NOT EXISTS idx_ai_cache_expires ON $tableAiResponseCache(expires_at)');
    }
    if (from < 16) {
      // v16 — Micro-coaching module cache + progress tables.
      Future<void> addTbl16(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* table already present */}
      }
      await addTbl16('''
        CREATE TABLE IF NOT EXISTS $tableCoachingModules (
          id TEXT PRIMARY KEY,
          domain TEXT NOT NULL,
          title_en TEXT NOT NULL,
          title_bn TEXT NOT NULL,
          estimated_minutes INTEGER NOT NULL DEFAULT 5,
          raw_json TEXT NOT NULL,
          priority_today INTEGER NOT NULL DEFAULT 0,
          synced_at INTEGER NOT NULL
        )''');
      await addTbl16('''
        CREATE TABLE IF NOT EXISTS $tableCoachingProgress (
          module_id TEXT PRIMARY KEY,
          passed INTEGER NOT NULL DEFAULT 0,
          quiz_score REAL NOT NULL DEFAULT 0.0,
          last_card_viewed INTEGER NOT NULL DEFAULT -1,
          updated_at INTEGER NOT NULL
        )''');
    }
    if (from < 17) {
      Future<void> addCol17(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* column already present */}
      }
      await addCol17('ALTER TABLE $tableMembers ADD COLUMN reference_id TEXT');
    }
    if (from < 18) {
      // v18 — Extended member demographic fields matching Android
      // HouseholdMemberEntity: maritalStatus, disability, guardianId,
      // guardianFhirId, latitude, longitude, idType.
      Future<void> addCol18(String ddl) async {
        try {
          await db.execute(ddl);
        } catch (_) {/* column already present */}
      }
      await addCol18('ALTER TABLE $tableMembers ADD COLUMN marital_status TEXT');
      await addCol18('ALTER TABLE $tableMembers ADD COLUMN disability TEXT');
      await addCol18('ALTER TABLE $tableMembers ADD COLUMN guardian_id TEXT');
      await addCol18('ALTER TABLE $tableMembers ADD COLUMN guardian_fhir_id TEXT');
      await addCol18('ALTER TABLE $tableMembers ADD COLUMN latitude REAL');
      await addCol18('ALTER TABLE $tableMembers ADD COLUMN longitude REAL');
      await addCol18('ALTER TABLE $tableMembers ADD COLUMN id_type TEXT');
    }
    if (from < 19) {
      // v19 — pregnancyEpisodeId on local_assessments, matching Android's
      // PregnancyDetails.pregnancyEpisodeId sent in offline-sync/create for
      // ANC/PNC encounters so the server can link sequential visits.
      try {
        await db.execute(
            'ALTER TABLE $tableLocalAssessments ADD COLUMN pregnancy_episode_id TEXT');
      } catch (_) {/* column already present */}
    }
    if (from < 20) {
      // v20 — Backfill patients.village_id with the sub-village ID from the
      // members table for any record that still holds the parent village ID.
      // Android scopes member-assessment-history pulls to sub-village IDs
      // (e.g. [203, 204, 206]) — assessments tagged with the parent village (34)
      // are invisible to Android. The offline_sync_service now writes
      // sub_village_id → patients.village_id for new syncs; this migration
      // repairs existing rows from before that fix.
      try {
        await db.execute('''
          UPDATE $tablePatients
          SET village_id = (
            SELECT sub_village_id FROM $tableMembers
            WHERE ($tableMembers.patient_id = $tablePatients.id
                   OR $tableMembers.id = $tablePatients.id)
              AND $tableMembers.sub_village_id IS NOT NULL
            LIMIT 1
          )
          WHERE EXISTS (
            SELECT 1 FROM $tableMembers
            WHERE ($tableMembers.patient_id = $tablePatients.id
                   OR $tableMembers.id = $tablePatients.id)
              AND $tableMembers.sub_village_id IS NOT NULL
          )
        ''');
      } catch (e) {
        // Non-fatal: existing records fall back to current villageId;
        // the next full sync will refresh them correctly.
        // ignore: avoid_print
        print('[DB v20] villageId backfill failed (non-fatal): $e');
      }
    }
    if (from < 21) {
      // v21 — Store EDD (epoch ms) on the pregnancy snapshot so Form 2 can
      // derive gestational age without requiring the server to include LMP in
      // individual assessment history rows.
      try {
        await db.execute(
          'ALTER TABLE $tablePregnancySnapshot ADD COLUMN edd_date INTEGER',
        );
      } catch (_) {/* column already present — safe to ignore */}
    }
    if (from < 22) {
      // v22 — Store LMP (epoch ms) directly from pregnancyInfos[].lmpDate.
      // Preferred over deriving from EDD; avoids rounding errors and handles
      // cases where server omits EDD but includes LMP.
      try {
        await db.execute(
          'ALTER TABLE $tablePregnancySnapshot ADD COLUMN lmp_date INTEGER',
        );
      } catch (_) {/* column already present — safe to ignore */}
    }
    if (from < 23) {
      // v23 — Remediation: devices that reached schemaVersion=22 before the
      // v21/v22 ALTER TABLE migrations were included in the build still lack
      // edd_date and/or lmp_date. Re-apply both; the try/catch makes this
      // idempotent if they already exist.
      try {
        await db.execute(
          'ALTER TABLE $tablePregnancySnapshot ADD COLUMN edd_date INTEGER',
        );
      } catch (_) {/* already present */}
      try {
        await db.execute(
          'ALTER TABLE $tablePregnancySnapshot ADD COLUMN lmp_date INTEGER',
        );
      } catch (_) {/* already present */}
    }

    if (from < 24) {
      // v24 — AI provenance on visit drafts: which draft values were filled
      // by the realtime ASR scribe (sources + verbatim transcript segments),
      // so restored drafts keep the "AI-filled — verify" marking.
      try {
        await db.execute(
          'ALTER TABLE $tableAssessmentDraft ADD COLUMN field_sources TEXT',
        );
      } catch (_) {/* already present */}
    }
  }

  // Single source of truth for "every table" — used by wipeAllData() so a
  // future new table can't be silently missed from a logout/login wipe.
  static const List<String> _allTables = [
    tableHouseholds, tableMembers, tablePatients, tableSyncMeta,
    tablePatientProgrammes, tableFollowUps, tableImmunisations, tableAssessments,
    tableReferrals, tableReferralStatusEvents, tableNotificationLog,
    tableEncounters, tableLocalAssessments, tablePregnancySnapshot,
    tableTreatmentPresence, tableAssessmentDraft, tableAiSuggestions,
    tableEvalLog, tableAiResponseCache, tableCoachingModules, tableCoachingProgress,
  ];

  /// Test-only view of [_allTables] so wipe tests can assert against the
  /// real list instead of duplicating it.
  static const List<String> allTablesForTesting = _allTables;

  /// Truncates every table, keeping the schema and the existing connection
  /// intact (no file delete/reopen — that would orphan every DAO's shared
  /// [Database] handle). Used on logout and after a successful online login,
  /// before the subsequent full sync repopulates local data.
  Future<void> wipeAllData() async {
    ConsoleLog.banner(
        '🧹 [AppDatabase] wipeAllData() — truncating ${_allTables.length} tables...');
    await db.transaction((tx) async {
      for (final table in _allTables) {
        final before = Sqflite.firstIntValue(
                await tx.rawQuery('SELECT COUNT(*) FROM $table')) ??
            0;
        await tx.delete(table);
        ConsoleLog.step(
            '  → truncated $table ($before row${before == 1 ? '' : 's'} removed)');
      }
    });
    ConsoleLog.success(
        '✅ [AppDatabase] wipeAllData() complete — all ${_allTables.length} tables empty.');
  }

  Future<void> close() => db.close();
}
