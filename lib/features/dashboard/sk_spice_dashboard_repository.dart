import '../../core/auth/auth_repository.dart';
import '../../core/db/member_assessment_history_dao.dart';
import '../../core/db/member_assessment_history_writer.dart';
import '../../core/db/spice_dashboard_dao.dart';

/// Loads SK KPI dashboard from local [member_assessment_history] (Spice SQL parity).
class SkSpiceDashboardRepository {
  SkSpiceDashboardRepository({
    required SpiceDashboardDao dashboard,
    required MemberAssessmentHistoryDao mah,
    required MemberAssessmentHistoryWriter mahWriter,
    required AuthRepository auth,
  })  : _dashboard = dashboard,
        _mah = mah,
        _mahWriter = mahWriter,
        _auth = auth;

  final SpiceDashboardDao _dashboard;
  final MemberAssessmentHistoryDao _mah;
  final MemberAssessmentHistoryWriter _mahWriter;
  final AuthRepository _auth;

  bool _mahHydrated = false;

  /// Call after offline sync so the next dashboard load rebuilds MAH from SQLite.
  void invalidateMahCache() => _mahHydrated = false;

  Future<SpiceDashboardCounts> load({
    required DateTime from,
    required DateTime to,
    List<String> ssIds = const [],
    List<String> subVillageIds = const [],
  }) async {
    if (!_mahHydrated) {
      _mahHydrated = true;
      if (await _mah.countAll() == 0) {
        await _mah.backfillFromLegacyAssessmentsTable();
      }
      // Same data Spice uses: full assessment-history cache + local visits.
      await _mahWriter.rebuildFromAssessmentsTable();
      await _mahWriter.rebuildFromLocalAssessments();
    }

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
