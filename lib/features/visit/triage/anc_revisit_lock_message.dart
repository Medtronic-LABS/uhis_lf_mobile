import '../../../core/constants/app_strings.dart';
import '../../../core/i18n/app_date_format.dart';
import '../../../core/time/calendar_day.dart';

/// Inputs for the Step 1 ANC revisit lock snackbar / dialog (not the card).
class AncRevisitLockInput {
  const AncRevisitLockInput({
    this.lastVisitMs,
    this.highRisk = false,
    this.revisitDays,
  });

  final int? lastVisitMs;
  final bool highRisk;
  final int? revisitDays;
}

/// Whether a new ANC visit is still inside the revisit window.
///
/// Uses **calendar-day** math (local midnight to midnight), matching Spice
/// `DateUtils.isIsoOffsetDateTimeOnLocalCalendarAfter` — not
/// `DateTime.difference(...).inDays`, which truncates toward zero and can
/// keep ANC locked on the day after a visit until 24 h have elapsed.
bool isAncRevisitTooSoon({
  required int lastVisitMs,
  required int revisitDays,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final daysSince = CalendarDay.daysBetween(
    DateTime.fromMillisecondsSinceEpoch(lastVisitMs),
    at,
  );
  return daysSince < revisitDays;
}

/// Resolved Step-1 ANC revisit lock from lookup inputs.
class AncRevisitLockResult {
  const AncRevisitLockResult({
    required this.tooSoon,
    this.lastVisitMs,
    this.highRisk = false,
    this.revisitDays,
  });

  final bool tooSoon;
  final int? lastVisitMs;
  final bool highRisk;
  final int? revisitDays;
}

/// Combines calendar-interval lock + same-calendar-day ANC guard.
///
/// [ancAssessmentToday] must win even when [lastVisitMs] is stale (e.g. points
/// at yesterday because the revisit query missed today's row under another id).
AncRevisitLockResult computeAncRevisitLock({
  required int? lastVisitMs,
  required bool highRisk,
  required bool ancAssessmentToday,
  DateTime? now,
}) {
  final revisitDays = highRisk ? 1 : 15;
  if (ancAssessmentToday) {
    return AncRevisitLockResult(
      tooSoon: true,
      // Null → same-day copy in Step 1 snackbar / card tooltip.
      lastVisitMs: null,
      highRisk: highRisk,
      revisitDays: revisitDays,
    );
  }
  if (lastVisitMs == null) {
    return AncRevisitLockResult(
      tooSoon: false,
      highRisk: highRisk,
      revisitDays: revisitDays,
    );
  }
  final tooSoon = isAncRevisitTooSoon(
    lastVisitMs: lastVisitMs,
    revisitDays: revisitDays,
    now: now,
  );
  return AncRevisitLockResult(
    tooSoon: tooSoon,
    lastVisitMs: lastVisitMs,
    highRisk: highRisk,
    revisitDays: revisitDays,
  );
}

/// Snackbar / dialog copy when the ANC card is revisit-locked.
///
/// Interval-based only (Spice `getAncMenuRevisitDays`) — never mentions a
/// stamped `nextVisitDate`.
String ancRevisitLockMessage(AncRevisitLockInput status) {
  final lastVisitMs = status.lastVisitMs;
  if (lastVisitMs == null) return TriageStrings.ancVisitedTodayMessage;
  final lastVisitStr = AppDateFormat.dayMonthYearFmt
      .format(DateTime.fromMillisecondsSinceEpoch(lastVisitMs));

  if (status.highRisk) {
    return TriageStrings.ancRevisitMessageHighRisk(lastVisit: lastVisitStr);
  }
  final days = status.revisitDays ?? 15;
  return TriageStrings.ancRevisitMessageNormalInterval(
    lastVisit: lastVisitStr,
    days: days,
  );
}
