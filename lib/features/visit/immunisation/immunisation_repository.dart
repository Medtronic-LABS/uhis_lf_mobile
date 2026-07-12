import 'dart:convert';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/db/immunisation_dao.dart';
import 'immunisation_dto.dart';

/// Repository for the EPI immunisation feature.
///
/// Mirrors the Android SPICE app's ImmunisationViewModel API contract:
///   POST /spice-service/immunisation/list   — fetch schedule (seeds local DB)
///   POST /spice-service/immunisation/create — push vaccine status updates
///   POST /spice-service/immunisation/summary-create — push visit summary
///
/// Offline-first: all writes persist to [ImmunisationDao] first; the network
/// call is best-effort and silent on failure so the SK flow is never blocked.
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

    final list = (response.data as List?)?.cast<Map<String, dynamic>>() ?? [];
    final dtos = list.map(VaccinationDetailDto.fromJson).toList();

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

  // ── Submit vaccinations ───────────────────────────────────────────────────

  /// Pushes updated vaccine statuses to the backend.
  ///
  /// [vaccines] must already reflect the new status ('Vaccinated' etc.).
  /// Call this after [ImmunisationDao.upsertMany] so local state is consistent
  /// even when the network call fails.
  Future<void> submitVaccinations({
    required String patientId,
    required String patientReference,
    required List<VaccinationDetailDto> vaccines,
    String? encounterId,
    String? missedReason,
  }) async {
    final encounter = MedicalReviewEncounterDto(
      patientReference: patientReference,
      patientId: int.tryParse(patientId) ?? 0,
    );

    final body = ImmunisationCreateRequestDto(
      immunisationList: vaccines,
      encounter: encounter,
      missedReason: missedReason,
    ).toJson();

    try {
      await _api.dio.post(Endpoints.immunisationCreate, data: body);
    } on Object {
      // Best-effort: local DB is already updated; log silently.
    }
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
