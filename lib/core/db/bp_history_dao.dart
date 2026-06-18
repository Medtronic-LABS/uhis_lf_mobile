/// BpHistoryDao — retrieves historical systolic BP readings per patient.
///
/// Queries [local_assessments] for NCD, ANC, and PNC rows belonging to the
/// patient, then extracts systolic BP from the stored JSON. Used by the CDSS
/// trend algorithms (CUSUM, EWMA, Linear Slope).
library;

import 'dart:convert';

import '../cdss/models/cdss_inputs.dart';
import 'app_database.dart';

class BpHistoryDao {
  BpHistoryDao(this._db);

  final AppDatabase _db;

  static const _tableName = 'local_assessments';

  // Programme types that carry BP readings.
  static const _bpTypes = ['NCD', 'ANC', 'PNC'];

  /// Returns systolic BP readings for [patientId], oldest first.
  ///
  /// Reads from assessmentDetails JSON. Tries three field shapes in order:
  ///   1. `avgSystolic` (NCD composite)
  ///   2. `bpLogDetails[0].systolic` (NCD log array)
  ///   3. `systolic` (ANC/PNC flat vitals)
  ///
  /// Rows where no BP can be extracted are silently skipped.
  /// [visitIndex] is assigned 0..n-1 (0 = oldest).
  Future<List<BpReading>> getForPatient(String patientId) async {
    final placeholders = _bpTypes.map((_) => '?').join(', ');
    final rows = await _db.db.query(
      _tableName,
      columns: ['assessment_details', 'created_at'],
      where: 'patient_id = ? AND assessment_type IN ($placeholders)',
      whereArgs: [patientId, ..._bpTypes],
      orderBy: 'created_at ASC',
    );

    final readings = <BpReading>[];
    for (final row in rows) {
      final systolic = _extractSystolic(row['assessment_details'] as String?);
      if (systolic != null) {
        readings.add(BpReading(
          systolic: systolic,
          visitIndex: readings.length,
        ));
      }
    }
    return readings;
  }

  static int? _extractSystolic(String? detailsJson) {
    if (detailsJson == null || detailsJson.isEmpty) return null;
    try {
      final map = jsonDecode(detailsJson);
      if (map is! Map<String, dynamic>) return null;

      // Shape 1: avgSystolic (NCD composite average)
      final avg = map['avgSystolic'];
      if (avg is num) return avg.round();

      // Shape 2: bpLogDetails array (NCD per-measurement log)
      final log = map['bpLogDetails'];
      if (log is List && log.isNotEmpty) {
        final first = log.first;
        if (first is Map) {
          final s = first['systolic'];
          if (s is num) return s.round();
        }
      }

      // Shape 3: flat systolic field (ANC/PNC vitals)
      final flat = map['systolic'];
      if (flat is num) return flat.round();

      return null;
    } catch (_) {
      return null;
    }
  }
}
