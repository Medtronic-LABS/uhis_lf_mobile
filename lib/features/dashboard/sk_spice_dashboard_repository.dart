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

  bool _mahHydrated = false;

  /// Call after offline sync so the next dashboard load rebuilds MAH from SQLite.
  void invalidateMahCache() => _mahHydrated = false;

  /// Re-merge [local_assessments] into MAH after a sync, then clean up.
  ///
  /// Sync has already written the server's rows. This does not rebuild from
  /// the [assessments] cache: that cache is never cleared, so rebuilding from
  /// it after a full sync brought back visits the server no longer has.
  Future<void> refreshMahFromLocalCaches() async {
    await _mahWriter.rebuildFromLocalAssessments();
    await _cleanUpMah();
    await _pregnancyDetail.rebuildAllFromMah();
    _mahHydrated = true;
  }

  /// Spice parity: no medical-review rows, and duplicates removed the way
  /// Spice does on every app start.
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
    if (!_mahHydrated) {
      _mahHydrated = true;
      // Fill from the cached history only when there is nothing yet (first
      // run before a history sync). Otherwise sync keeps the table current,
      // and rebuilding from the never-cleared cache would undo a full sync.
      if (await _mah.countAll() == 0) {
        await _mah.backfillFromLegacyAssessmentsTable();
        await _mahWriter.rebuildFromAssessmentsTable();
      }
      await _mahWriter.rebuildFromLocalAssessments();
      await _cleanUpMah();
    }
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

  static String _dateYmd(DateTime d) {
    final local = d.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
