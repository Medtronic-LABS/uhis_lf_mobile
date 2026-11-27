import '../../core/auth/auth_repository.dart';
import '../../core/db/member_assessment_history_dao.dart';
import '../../core/db/member_assessment_history_writer.dart';
import '../../core/db/pregnancy_detail_dao.dart';
import '../../core/db/spice_dashboard_dao.dart';

/// Loads SK KPI dashboard from local [member_assessment_history] (Spice SQL parity).
class SkSpiceDashboardRepository {
  SkSpiceDashboardRepository({
    required SpiceDashboardDao dashboard,
    required MemberAssessmentHistoryDao mah,
    required MemberAssessmentHistoryWriter mahWriter,
    required PregnancyDetailDao pregnancyDetail,
    required AuthRepository auth,
  })  : _dashboard = dashboard,
        _mah = mah,
        _mahWriter = mahWriter,
        _pregnancyDetail = pregnancyDetail,
        _auth = auth;

  final SpiceDashboardDao _dashboard;
  final MemberAssessmentHistoryDao _mah;
  final MemberAssessmentHistoryWriter _mahWriter;
  final PregnancyDetailDao _pregnancyDetail;
  final AuthRepository _auth;

  /// The one hydration of this session. Every [load] waits for it, so a
  /// second load started while it runs cannot count a half-updated table.
  Future<void>? _hydration;

  /// Makes the next [load] hydrate again.
  void invalidateMahCache() => _hydration = null;

  /// Re-merge [local_assessments] into MAH after a sync, then clean up.
  ///
  /// Sync has already written the server's rows. This does not rebuild from
  /// the [assessments] cache: that cache is never cleared, so rebuilding from
  /// it after a full sync brought back visits the server no longer has.
  Future<void> refreshMahFromLocalCaches() async {
    await _mahWriter.rebuildFromLocalAssessments();
    await _cleanUpMah();
    await _pregnancyDetail.rebuildAllFromMah();
  }

  /// No medical-review rows (as in Spice), and no row repeating an encounter
  /// id + service. Runs on every hydration and after every sync.
  Future<void> _cleanUpMah() async {
    await _mah.deleteMedicalReviewRows();
    await _mah.deleteDuplicateRecords();
  }

  Future<SpiceDashboardCounts> load({
    required DateTime from,
    required DateTime to,
    List<String> ssIds = const [],
    List<String> subVillageIds = const [],
  }) async {
    await _ensureHydrated();
    await _pregnancyDetail.rebuildAllFromMah();

    final start = _dateYmd(from);
    final end = _dateYmd(to);
    final userFhirId = await _auth.userFhirId();

    return _dashboard.loadCounts(
      startDate: start,
      endDate: end,
      ssIds: ssIds,
      subVillageIds: subVillageIds,
      userFhirId: userFhirId,
    );
  }

  Future<void> _ensureHydrated() {
    final running = _hydration;
    if (running != null) return running;
    late final Future<void> started;
    started = hydrateMah().catchError((Object e, StackTrace st) {
      // Let the next load try again instead of skipping hydration all session.
      if (identical(_hydration, started)) _hydration = null;
      Error.throwWithStackTrace(e, st);
    });
    return _hydration = started;
  }

  /// Brings the history table up to date before the first count of a session.
  Future<void> hydrateMah() async {
    if (await _mah.countAll() == 0) {
      // Nothing yet (first run before a history sync): fill from the cache.
      await _mah.backfillFromLegacyAssessmentsTable();
      await _mahWriter.rebuildFromAssessmentsTable();
      await _mahWriter.markNormalized();
    } else if (await _mahWriter.needsNormalize()) {
      // Parse rules changed since these rows were written: re-write the
      // visits already here. Not a full rebuild, because the cache is never
      // cleared and that would bring back visits a full sync removed.
      await _mahWriter.rebuildFromAssessmentsTable(onlyExisting: true);
      await _mahWriter.markNormalized();
    }
    await _mahWriter.rebuildFromLocalAssessments();
    await _cleanUpMah();
  }

  static String _dateYmd(DateTime d) {
    final local = d.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
