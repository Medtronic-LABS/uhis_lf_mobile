import '../../core/db/referral_dao.dart';
import '../../core/debug/console_log.dart';
import '../../core/models/referral.dart';
import '../../core/referral/referral_ingest_mapper.dart';
import 'referral_api_service.dart';
import 'referral_repository.dart';

/// Orchestrates the live referral-status fetch pipeline for a single patient:
///   fetch → map → persist → SLA recompute.
///
/// Called from PatientContextScreen on load so the SK sees the nurse medical
/// review outcome (patientStatus: Controlled / Uncontrolled) without waiting
/// for the next full offline sync.
///
/// The service is stateless — callers own lifecycle and provide context.
/// All errors are caught and logged; the screen degrades to the SQLite
/// snapshot on failure (offline-first contract).
class ReferralFetchService {
  const ReferralFetchService({
    required ReferralApiService api,
    required ReferralDao dao,
    required ReferralRepository repository,
  })  : _api = api,
        _dao = dao,
        _repo = repository;

  final ReferralApiService _api;
  final ReferralDao _dao;
  final ReferralRepository _repo;

  /// Fetch referral tickets for [patientId], persist to SQLite, recompute SLA.
  ///
  /// After [_dao.upsertMany], [ReferralRepository.recomputeAllAfterSync] runs
  /// the SLA engine and fires `_changes.value++` — this propagates to
  /// CceRepository.changes, which the dashboard already listens to. CCE
  /// alerts update automatically at zero extra cost.
  ///
  /// Returns the count of ingested rows (0 on error or empty response).
  Future<int> fetchAndPersist({
    required String patientId,
    String? memberId,
    String? householdId,
    String? villageId,
  }) async {
    ConsoleLog.step(
      '[ReferralFetchService] fetchAndPersist start — patientId=$patientId memberId=$memberId',
    );

    final tickets = await _api.fetchReferrals(
      patientId: patientId,
      memberId: memberId,
    );

    if (tickets.isEmpty) {
      ConsoleLog.step('[ReferralFetchService] no tickets returned — skipping persist');
      return 0;
    }

    // Map wire tickets → domain Referral rows.
    final rows = tickets
        .map(
          (t) => ReferralIngestMapper.fromReferralTicket(
            t,
            patientId: patientId,
            householdId: householdId,
            villageId: villageId,
          ),
        )
        .whereType<Referral>()
        .toList(growable: false);

    if (rows.isEmpty) {
      // All tickets were malformed (no id) — nothing to persist.
      ConsoleLog.step('[ReferralFetchService] all tickets malformed — skipping persist');
      return 0;
    }

    // DEBUG: log each ingested referral state for field-level tracing.
    for (final r in rows) {
      ConsoleLog.step(
        '[ReferralFetchService] ingest id=${r.id} state=${r.state.wireTag} '
        'slaTier=${r.slaTier.wireTag} diagnosis=${r.diagnosisLabel}',
      );
    }

    await _dao.upsertMany(rows);

    // Recompute SLA + priority for all open referrals.
    // This fires _changes.value++ → CceRepository.changes notifies dashboard.
    await _repo.recomputeAllAfterSync();

    ConsoleLog.step(
      '[ReferralFetchService] fetchAndPersist done — persisted=${rows.length}',
    );
    return rows.length;
  }
}
