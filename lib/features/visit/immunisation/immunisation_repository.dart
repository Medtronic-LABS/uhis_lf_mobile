import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/db/immunisation_dao.dart';
import 'immunisation_dto.dart';

/// Repository for the EPI immunisation feature — read path only.
///
/// Mirrors the Android SPICE app's ImmunisationViewModel API contract:
///   POST /spice-service/immunisation/list   — fetch schedule (seeds local DB)
///   POST /spice-service/immunisation/summary-create — push visit summary
///
/// Recording a vaccine's outcome (Vaccinated/Missed + referral) no longer
/// pushes here — see ImmunisationTimelineScreen's _UpdateStatusSheet, which
/// syncs via AssessmentRepository.saveAssessment(assessmentType:
/// 'CHILD_IMMUNIZATION') → POST /offline-service/offline-sync/create,
/// the same offline-first queued/retried pipeline every other assessment
/// type uses, replacing the old best-effort/silent-fail submitVaccinations().
///
/// Offline-first: fetchSchedule's writes persist to [ImmunisationDao] first.
class ImmunisationRepository {
  ImmunisationRepository(this._api, this._dao);

  final ApiClient _api;
  final ImmunisationDao _dao;

  // ── Fetch ─────────────────────────────────────────────────────────────────

  /// Fetches the immunisation schedule from the backend and seeds local DB.
  /// Returns the raw [VaccinationDetailDto] list for callers that need it.
  Future<List<VaccinationDetailDto>> fetchSchedule({
    required String patientId,
    required String patientReference,
    required String birthDate,
    String? memberId,
  }) async {
    final body = ImmunisationListRequestDto(
      patientReference: patientReference,
      patientId: int.tryParse(patientId) ?? 0,
      birthDate: birthDate,
      memberId: memberId,
    ).toJson();

    final response = await _api.dio.post(
      Endpoints.immunisationList,
      data: body,
    );

    if (response.statusCode != 200) return const [];

    // Backend wraps the list: {"entityList":[...], "status":true, ...}
    // Fall back to bare List if the server ever changes to unwrapped form.
    final raw = response.data;
    final rawList = raw is List
        ? raw
        : (raw is Map && raw['entityList'] is List
            ? raw['entityList'] as List
            : null);
    if (rawList == null || rawList.isEmpty) return const [];
    final list = rawList.whereType<Map<String, dynamic>>().toList();
    final dtos = list.map(VaccinationDetailDto.fromJson).toList();
    debugPrint(
      '[ImmunisationRepository] fetchSchedule: ${dtos.length} vaccines from backend',
    );

    // Seed local DB from backend response
    final rows = dtos.map((dto) {
      final dueMs = _parseIsoMs(dto.scheduledDate);
      final givenMs = dto.vaccinatedDate != null
          ? _parseIsoMs(dto.vaccinatedDate!)
          : null;
      return ImmunisationRow(
        id: '${patientId}_${dto.vaccineName}_${dto.scheduledDate}',
        patientId: patientId,
        vaccineCode: dto.vaccineName,
        dueAt: dueMs,
        givenAt: givenMs,
        rawJson: jsonEncode(dto.toJson()),
      );
    }).toList();

    await _dao.upsertMany(rows);
    return dtos;
  }

  // ── Summary ───────────────────────────────────────────────────────────────

  /// Posts the immunisation visit summary (vaccinated count, next visit etc.)
  Future<void> createSummary(ImmunisationSummaryCreateDto dto) async {
    try {
      await _api.dio.post(
        Endpoints.immunisationSummaryCreate,
        data: dto.toJson(),
      );
    } on Object {
      // Best-effort.
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static int? _parseIsoMs(String iso) {
    final dt = DateTime.tryParse(iso);
    return dt?.millisecondsSinceEpoch;
  }
}
