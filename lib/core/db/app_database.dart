import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite store for the offline cache (households, members, patients)
/// plus per-entity sync bookkeeping. Schema v2 added the AI Worklist tables
/// (programmes, follow_ups, immunisations, assessments) and the risk columns
/// on `patients`. Schema v3 adds the Referral SLA tables (referrals,
/// referral_status_events, notification_log) — see
/// `leapfrog-setup/designs/referral-sla-engine.md`.
///
/// ⚠️ Plain SQLite — the data is NOT encrypted at rest (a pilot-phase choice,
/// see the plan's risk note). Migrate to SQLCipher before non-pilot
/// deployment; the schema + DAO layer are unchanged by that swap.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int schemaVersion = 3;
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

  /// Opens (creating if needed) the on-device database.
  static Future<AppDatabase> open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _fileName);
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: createSchema,
      onUpgrade: _onUpgrade,
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
        household_no TEXT,
        name TEXT,
        village TEXT,
        village_id TEXT,
        member_count INTEGER,
        updated_at INTEGER,
        raw_json TEXT
      )''');
    await db.execute('''
      CREATE TABLE $tableMembers (
        id TEXT PRIMARY KEY,
        household_id TEXT,
        name TEXT,
        gender TEXT,
        dob TEXT,
        phone TEXT,
        national_id TEXT,
        patient_id TEXT,
        village_id TEXT,
        is_active INTEGER,
        updated_at INTEGER,
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
        is_active INTEGER,
        updated_at INTEGER,
        raw_json TEXT,
        age INTEGER,
        risk_score INTEGER,
        risk_band TEXT,
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
  }

  Future<void> close() => db.close();
}
