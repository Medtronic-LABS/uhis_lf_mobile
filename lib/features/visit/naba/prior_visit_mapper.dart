/// Maps stored visit history onto the NABA request's prior-visit shape.
///
/// Kept out of the screen so the parsing can be tested without a widget tree,
/// and pure Dart so it carries no Flutter dependency.
///
/// **Every value arrives as a string.** The synced `observations` map is the
/// flat server shape documented in CLAUDE.md — `bp: "144/91"`, `bg: "7.2"`,
/// `weight: "58"` — so each field needs parsing, and a field that cannot be
/// parsed must become `null` rather than an empty string: the server's
/// `VitalSnapshot` types are `int`/`float`, and `""` or `"N/A"` reaching one
/// of them 422s the whole request. [NabaVitalSnapshot.toJson] omits nulls, so
/// returning null is what keeps a bad reading out of the payload entirely.
library;

import '../../../core/models/assessment_history_item.dart';
import 'naba_models.dart';

abstract final class PriorVisitMapper {
  PriorVisitMapper._();

  /// One stored encounter as the backend's `PriorVisitSummary`.
  static NabaPriorVisit from(AssessmentHistoryItem item) => NabaPriorVisit(
        date: _isoDate(item.visitDate),
        programme: _trimToNull(item.serviceProvided),
        keyFindings: _keyFindings(item),
        actionsTaken: _actionsTaken(item),
        vitals: vitalsFromObservations(item.observations),
      );

  /// Date only, never a timestamp and never an epoch int.
  ///
  /// The server declares `date: str` and Pydantic v2 does not coerce int to
  /// str, so a number 422s. Date-only also reads better in the prompt, which
  /// renders this verbatim as `- {date} [{programme}]: …`.
  static String _isoDate(DateTime d) {
    final local = d.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// What was found: the visit's statuses plus the referral reason.
  static List<String> _keyFindings(AssessmentHistoryItem item) {
    final out = <String>{
      for (final s in item.customStatus) ...[
        if (s.trim().isNotEmpty) s.trim(),
      ],
    };
    final reason = _trimToNull(item.referralReason);
    if (reason != null) out.add(reason);
    return out.toList(growable: false);
  }

  /// What was done: referral outcome and any follow-up that was booked.
  ///
  /// A booked follow-up is an action already taken, and is what lets the model
  /// avoid proposing a second one for the same thing.
  static List<String> _actionsTaken(AssessmentHistoryItem item) {
    final out = <String>[];
    final status = _trimToNull(item.referralStatus);
    if (status != null) out.add(status);
    final next = item.nextFollowUpDate;
    if (next != null) out.add('Follow-up due ${_isoDate(next)}');
    return out;
  }

  /// Vitals from the flat synced `observations` map.
  ///
  /// Returns null when nothing could be parsed, so the `vitals` key is omitted
  /// rather than sent as an empty object.
  static NabaVitalSnapshot? vitalsFromObservations(
    Map<String, dynamic>? observations,
  ) {
    if (observations == null || observations.isEmpty) return null;

    final (systolic, diastolic) = splitBloodPressure(observations['bp']);
    final glucose = toDouble(observations['bg']);
    final fasting = isFastingGlucose(observations['bgType']);

    final snapshot = NabaVitalSnapshot(
      bloodPressureSystolic: systolic,
      bloodPressureDiastolic: diastolic,
      weight: toDouble(observations['weight']),
      temperature: toDouble(observations['temperature']),
      glucoseFasting: fasting ? glucose : null,
      glucoseRandom: fasting ? null : glucose,
      // Only when there is a reading to qualify. The observations map carries
      // no unit of its own, and mmol/L is this app's convention everywhere
      // else (see unified_payload_mapper and _parseNcdVitals). Stating it
      // explicitly matters: mmol/L and mg/dL differ by ~18x, so a glucose of
      // 4.0 read under the wrong unit is a confidently wrong recommendation.
      glucoseUnit: glucose == null ? null : _kGlucoseUnit,
      heartRate: toInt(observations['pulse']),
      bmi: toDouble(observations['bmi']),
    );

    return _isEmpty(snapshot) ? null : snapshot;
  }

  static const String _kGlucoseUnit = 'mmol/L';

  /// `"144/91"` to its two halves. Either half may fail independently.
  ///
  /// Returns `(null, null)` for anything that is not two parts — the whole
  /// string would otherwise reach an `int` field and 422.
  static (int?, int?) splitBloodPressure(Object? raw) {
    if (raw == null) return (null, null);
    final parts = raw.toString().split('/');
    if (parts.length != 2) return (null, null);
    return (toInt(parts[0]), toInt(parts[1]));
  }

  /// True for a fasting sample. The server splits glucose into
  /// `glucoseFasting` and `glucoseRandom`; there is no plain `glucose` field,
  /// and a value sent under the wrong one is simply wrong rather than refused.
  static bool isFastingGlucose(Object? bgType) {
    final t = bgType?.toString().trim().toUpperCase() ?? '';
    return t.startsWith('F') || t.contains('FAST');
  }

  /// A number from whatever the map holds, or null. Never throws.
  static double? toDouble(Object? raw) {
    if (raw == null) return null;
    if (raw is num) {
      return raw.isFinite ? raw.toDouble() : null;
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final parsed = double.tryParse(s);
    return (parsed == null || !parsed.isFinite) ? null : parsed;
  }

  /// An integer for the server's `int` fields.
  ///
  /// Rounded, not truncated or passed through: a fractional value in an `int`
  /// field 422s, and these are whole-number measurements in practice.
  static int? toInt(Object? raw) {
    final d = toDouble(raw);
    return d?.round();
  }

  static bool _isEmpty(NabaVitalSnapshot v) =>
      v.bloodPressureSystolic == null &&
      v.bloodPressureDiastolic == null &&
      v.weight == null &&
      v.temperature == null &&
      v.glucoseFasting == null &&
      v.glucoseRandom == null &&
      v.spO2 == null &&
      v.heartRate == null &&
      v.bmi == null;

  static String? _trimToNull(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
