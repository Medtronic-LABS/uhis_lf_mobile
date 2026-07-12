import 'dart:convert';

import '../../../core/db/patient_dao.dart';
import '../../../core/db/patient_programmes_dao.dart';
import '../../../core/db/pregnancy_snapshot_dao.dart';
import '../../../core/mission/mission_pregnancy_facts.dart';
import '../../../core/models/programme.dart';

/// Sex of the patient for pathway gating.
enum Sex { male, female, unknown }

/// Patient context for pathway activation.
///
/// Built from local SQLite/FHIR cache. Contains all demographic and clinical
/// facts needed by the [PathwayEngine] to determine activated pathways.
class PatientContext {
  const PatientContext({
    required this.patientId,
    required this.ageMonths,
    required this.sex,
    required this.isPregnant,
    this.ageKnown = true,
    this.gestationalWeeks,
    this.pregnancyFacts,
    this.deliveryDateMillis,
    this.gravida,
    this.para,
    this.knownConditions = const {},
    this.activeProgrammes = const {},
    this.lastBpSystolic,
    this.lastBpDiastolic,
    this.lastGlucose,
    this.overdueImmunizations = const [],
    this.openFlags = const {},
  });

  /// FHIR patient ID.
  final String patientId;

  /// Age in months. 0 for < 1 month old.
  final int ageMonths;

  /// Whether [ageMonths] comes from real data (DOB or recorded age).
  ///
  /// False when the local record has neither, in which case [ageMonths]
  /// defaults to 0 — age-based gates must NOT treat that as "newborn".
  final bool ageKnown;

  /// Sex for demographic gating.
  final Sex sex;

  /// Whether the patient is currently pregnant.
  final bool isPregnant;

  /// Gestational weeks if pregnant.
  final int? gestationalWeeks;

  /// Pregnancy risk and status facts from sync.
  final PregnancyFacts? pregnancyFacts;

  /// Delivery date in milliseconds since epoch, for PNC window calculation.
  final int? deliveryDateMillis;

  /// Total number of pregnancies (including current), from patient record.
  /// Null if not recorded.
  final int? gravida;

  /// Number of completed deliveries (Para), from patient record.
  /// Null if not recorded.
  final int? para;

  /// Known diagnosis codes (ICD-10/SNOMED) from active Conditions.
  /// Used for history-triggered pathways (e.g., known HTN, prior TB).
  final Set<String> knownConditions;

  /// Currently enrolled programmes from patient_programmes table.
  final Set<Programme> activeProgrammes;

  /// Last recorded systolic BP (mmHg) from vitals history.
  final int? lastBpSystolic;

  /// Last recorded diastolic BP (mmHg) from vitals history.
  final int? lastBpDiastolic;

  /// Last recorded blood glucose (mg/dL) from vitals history.
  final double? lastGlucose;

  /// Overdue immunization names/codes from EPI schedule.
  final List<String> overdueImmunizations;

  /// Open flags that trigger scheduled pathways.
  /// Examples: TB_SCREEN_DUE, FP_COUNSELLING_DUE, EPI_DUE
  final Set<String> openFlags;

  /// Returns age in years (rounded down).
  int get ageYears => ageMonths ~/ 12;

  /// Whether patient is a neonate (< 2 months).
  bool get isNeonate => ageMonths < 2;

  /// Whether patient is an infant (< 12 months).
  bool get isInfant => ageMonths < 12;

  /// Whether patient is under 5 years old.
  bool get isUnder5 => ageMonths < 60;

  /// Whether patient is an adult (18+ years).
  bool get isAdult => ageMonths >= 216; // 18 * 12

  /// Whether patient is female.
  bool get isFemale => sex == Sex.female;

  /// Whether patient is in the postpartum window (< 6 weeks post-delivery).
  bool get isPostpartum {
    if (deliveryDateMillis == null) return false;
    final deliveryDate = DateTime.fromMillisecondsSinceEpoch(deliveryDateMillis!);
    final now = DateTime.now();
    return now.difference(deliveryDate).inDays < 42; // 6 weeks
  }

  /// Whether patient has known hypertension.
  bool get hasKnownHypertension {
    return knownConditions.any((c) =>
        c.toUpperCase().contains('HYPERTENSION') ||
        c.toUpperCase().contains('HTN') ||
        c.toUpperCase() == 'I10' || // ICD-10 Essential HTN
        c.toUpperCase().startsWith('I1')); // ICD-10 HTN range
  }

  /// Whether patient has known diabetes.
  bool get hasKnownDiabetes {
    return knownConditions.any((c) =>
        c.toUpperCase().contains('DIABETES') ||
        c.toUpperCase().contains('DM') ||
        c.toUpperCase().startsWith('E11') || // ICD-10 Type 2
        c.toUpperCase().startsWith('E10')); // ICD-10 Type 1
  }

  /// Whether patient has prior TB history.
  bool get hasPriorTb {
    return knownConditions.any((c) =>
        c.toUpperCase().contains('TB') ||
        c.toUpperCase().contains('TUBERCULOSIS') ||
        c.toUpperCase().startsWith('A15') || // ICD-10 Respiratory TB
        c.toUpperCase().startsWith('A16'));
  }

  /// Whether TB screening is due per open flags.
  bool get isTbScreenDue => openFlags.contains('TB_SCREEN_DUE');

  /// Whether EPI is due (has overdue immunizations).
  bool get isEpiDue => overdueImmunizations.isNotEmpty;

  /// Whether last BP reading was elevated (≥140/90).
  bool get hasElevatedBp {
    if (lastBpSystolic == null || lastBpDiastolic == null) return false;
    return lastBpSystolic! >= 140 || lastBpDiastolic! >= 90;
  }
}

/// Builds [PatientContext] from local database DAOs.
///
/// This is the repository-layer component that assembles patient facts
/// from multiple local tables for the pathway engine.
class PatientContextBuilder {
  PatientContextBuilder({
    required PatientDao patientDao,
    required PatientProgrammesDao programmesDao,
    required PregnancySnapshotDao pregnancyDao,
  })  : _patientDao = patientDao,
        _programmesDao = programmesDao,
        _pregnancyDao = pregnancyDao;

  final PatientDao _patientDao;
  final PatientProgrammesDao _programmesDao;
  final PregnancySnapshotDao _pregnancyDao;

  /// Build patient context from local cache.
  ///
  /// Returns null if the patient is not found in the local database.
  Future<PatientContext?> build(String patientId) async {
    // Fetch patient record
    final patient = await _patientDao.byId(patientId);
    if (patient == null) return null;

    // Fetch enrolled programmes
    final programmes = await _programmesDao.programmesFor(patientId);

    // Fetch pregnancy facts if available
    final pregnancyMap = await _pregnancyDao.getAll();
    final pregnancyFacts = pregnancyMap[patientId];

    // Calculate age in months
    final ageMonths = _calculateAgeMonths(patient.dob, patient.age);
    final ageKnown =
        (patient.dob != null && patient.dob!.isNotEmpty) || patient.age != null;

    // Determine sex
    final sex = _parseSex(patient.gender);

    // Determine pregnancy status
    final isPregnant = pregnancyFacts != null ||
        programmes.contains(Programme.anc) ||
        _isPregnantFromRaw(patient.rawJson);

    // Extract gestational weeks from raw JSON if available
    final gestationalWeeks = _extractGestationalWeeks(patient.rawJson);

    // Extract known conditions from raw JSON
    final knownConditions = _extractConditions(patient.rawJson);

    // Extract delivery date for PNC
    final deliveryDateMillis = _extractDeliveryDate(patient.rawJson);

    // Get overdue immunizations (Phase 4 sync-payload gap — return empty for now)
    // TODO: Wire up ImmunisationDao once EPI sync is implemented
    final overdueImmunizations = <String>[];

    // Build open flags from follow-up data
    final openFlags = await _buildOpenFlags(patientId);

    // Extract last vitals from raw JSON or assessment history
    final (lastBpSystolic, lastBpDiastolic) = _extractLastBp(patient.rawJson);
    final lastGlucose = _extractLastGlucose(patient.rawJson);
    final (gravida, para) = _extractGravidaPara(patient.rawJson);

    return PatientContext(
      patientId: patientId,
      ageMonths: ageMonths,
      ageKnown: ageKnown,
      sex: sex,
      isPregnant: isPregnant,
      gestationalWeeks: gestationalWeeks,
      pregnancyFacts: pregnancyFacts,
      deliveryDateMillis: deliveryDateMillis,
      gravida: gravida,
      para: para,
      knownConditions: knownConditions,
      activeProgrammes: programmes,
      lastBpSystolic: lastBpSystolic,
      lastBpDiastolic: lastBpDiastolic,
      lastGlucose: lastGlucose,
      overdueImmunizations: overdueImmunizations,
      openFlags: openFlags,
    );
  }

  int _calculateAgeMonths(String? dob, int? ageYears) {
    if (dob != null && dob.isNotEmpty) {
      try {
        final birthDate = DateTime.parse(dob);
        final now = DateTime.now();
        final months = (now.year - birthDate.year) * 12 +
            now.month -
            birthDate.month;
        // Adjust if day of month hasn't passed yet
        if (now.day < birthDate.day && months > 0) {
          return months - 1;
        }
        return months;
      } catch (_) {
        // Fall through to age-based calculation
      }
    }

    // Fall back to age in years converted to months
    if (ageYears != null) {
      return ageYears * 12;
    }

    return 0; // Default to 0 if no age data
  }

  Sex _parseSex(String? gender) {
    if (gender == null) return Sex.unknown;
    final g = gender.toUpperCase().trim();
    if (g == 'M' || g == 'MALE') return Sex.male;
    if (g == 'F' || g == 'FEMALE') return Sex.female;
    return Sex.unknown;
  }

  bool _isPregnantFromRaw(String rawJson) {
    try {
      final json = jsonDecode(rawJson) as Map<String, dynamic>;
      // Check various pregnancy indicators
      if (json['isPregnant'] == true) return true;
      if (json['pregnancyStatus'] == 'ACTIVE') return true;
      if (json['isPregnancyActive'] == true) return true;
      // Check diagnosis types
      final diagTypes = json['diagnosisType'] as List?;
      if (diagTypes != null) {
        for (final t in diagTypes) {
          final s = t.toString().toUpperCase();
          if (s == 'ANC' || s == 'PREGNANCY' || s == 'PREGNANT') return true;
        }
      }
    } catch (_) {}
    return false;
  }

  int? _extractGestationalWeeks(String rawJson) {
    try {
      final json = jsonDecode(rawJson) as Map<String, dynamic>;
      if (json['gestationalWeeks'] != null) {
        return (json['gestationalWeeks'] as num).toInt();
      }
      // Calculate from LMP if available
      if (json['lmpDate'] != null) {
        final lmp = DateTime.tryParse(json['lmpDate'] as String);
        if (lmp != null) {
          return DateTime.now().difference(lmp).inDays ~/ 7;
        }
      }
    } catch (_) {}
    return null;
  }

  Set<String> _extractConditions(String rawJson) {
    final conditions = <String>{};
    try {
      final json = jsonDecode(rawJson) as Map<String, dynamic>;

      // Extract from diagnosisType array
      final diagTypes = json['diagnosisType'] as List?;
      if (diagTypes != null) {
        for (final t in diagTypes) {
          conditions.add(t.toString().toUpperCase());
        }
      }

      // Extract from conditions array if present
      final condList = json['conditions'] as List?;
      if (condList != null) {
        for (final c in condList) {
          if (c is Map) {
            final code = c['code']?.toString() ?? c['icdCode']?.toString();
            if (code != null) conditions.add(code.toUpperCase());
          } else if (c is String) {
            conditions.add(c.toUpperCase());
          }
        }
      }

      // Check for specific condition flags
      if (json['isHypertensive'] == true) conditions.add('HYPERTENSION');
      if (json['isDiabetic'] == true) conditions.add('DIABETES');
      if (json['isTbPatient'] == true) conditions.add('TB');
    } catch (_) {}
    return conditions;
  }

  int? _extractDeliveryDate(String rawJson) {
    try {
      final json = jsonDecode(rawJson) as Map<String, dynamic>;
      if (json['deliveryDate'] != null) {
        final date = DateTime.tryParse(json['deliveryDate'] as String);
        if (date != null) return date.millisecondsSinceEpoch;
      }
      if (json['dateOfDelivery'] != null) {
        final date = DateTime.tryParse(json['dateOfDelivery'] as String);
        if (date != null) return date.millisecondsSinceEpoch;
      }
    } catch (_) {}
    return null;
  }

  (int?, int?) _extractLastBp(String rawJson) {
    try {
      final json = jsonDecode(rawJson) as Map<String, dynamic>;

      // Try direct BP fields
      final systolic = json['bpSystolic'] ?? json['systolicBp'];
      final diastolic = json['bpDiastolic'] ?? json['diastolicBp'];
      if (systolic != null && diastolic != null) {
        return ((systolic as num).toInt(), (diastolic as num).toInt());
      }

      // Try lastVitals object
      final vitals = json['lastVitals'] as Map?;
      if (vitals != null) {
        final s = vitals['bpSystolic'] ?? vitals['systolicBp'];
        final d = vitals['bpDiastolic'] ?? vitals['diastolicBp'];
        if (s != null && d != null) {
          return ((s as num).toInt(), (d as num).toInt());
        }
      }

      // Try bpLog array (most recent first)
      final bpLogs = json['bpLogs'] as List?;
      if (bpLogs != null && bpLogs.isNotEmpty) {
        final log = bpLogs.first as Map;
        final s = log['systolic'] ?? log['bpSystolic'];
        final d = log['diastolic'] ?? log['bpDiastolic'];
        if (s != null && d != null) {
          return ((s as num).toInt(), (d as num).toInt());
        }
      }
    } catch (_) {}
    return (null, null);
  }

  (int?, int?) _extractGravidaPara(String rawJson) {
    try {
      final json = jsonDecode(rawJson) as Map<String, dynamic>;
      final g = json['gravida'] ?? json['noOfGravida'] ?? json['numberOfGravida'];
      final p = json['para'] ?? json['parity'] ?? json['noOfDeliveries'] ?? json['numberOfDeliveries'];
      final gravida = g != null ? (g as num).toInt() : null;
      final para = p != null ? (p as num).toInt() : null;
      return (gravida, para);
    } catch (_) {}
    return (null, null);
  }

  double? _extractLastGlucose(String rawJson) {
    try {
      final json = jsonDecode(rawJson) as Map<String, dynamic>;

      // Try direct glucose field
      final glucose = json['bloodGlucose'] ?? json['glucoseValue'];
      if (glucose != null) {
        return (glucose as num).toDouble();
      }

      // Try lastVitals object
      final vitals = json['lastVitals'] as Map?;
      if (vitals != null) {
        final g = vitals['bloodGlucose'] ?? vitals['glucoseValue'];
        if (g != null) {
          return (g as num).toDouble();
        }
      }

      // Try glucoseLog array (most recent first)
      final logs = json['glucoseLogs'] as List?;
      if (logs != null && logs.isNotEmpty) {
        final log = logs.first as Map;
        final g = log['glucoseValue'] ?? log['value'];
        if (g != null) {
          return (g as num).toDouble();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Set<String>> _buildOpenFlags(String patientId) async {
    final flags = <String>{};

    // TODO: Build from follow-up data once FollowUpDao is wired
    // if (_followUpDao != null) {
    //   final followUps = await _followUpDao!.byPatientId(patientId);
    //   for (final f in followUps) {
    //     if (f.type == 'TB_SCREENING' && f.completedAt == null) {
    //       flags.add('TB_SCREEN_DUE');
    //     }
    //   }
    // }

    return flags;
  }
}
