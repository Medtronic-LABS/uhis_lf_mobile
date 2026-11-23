import 'package:connectivity_plus/connectivity_plus.dart';

import 'analytics.dart';
import 'analytics_events.dart';

/// GA (LEAP-152): registration events — NID scans, the home sheet choice,
/// households created and members added. Only outcomes, counts and flags are
/// sent; never names, NID numbers or dates of birth.

/// `'true'` / `'false'`, or `'unknown'` when the lookup could not run.
String existingPatientValue(bool? found) =>
    found == null ? AnalyticsValue.unknown : '$found';

/// One NID scanner session → one `nid_scan_result` when it closes.
class GaNidScan {
  GaNidScan(this.source, {int Function()? clock})
      : _clock = clock ?? _wallClock {
    _openedAtMs = _clock();
  }

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  /// fab / search_scan (home sheet) or members_list / household_detail /
  /// add_member (member scanner). Null when the opener is unknown.
  final String? source;
  final int Function() _clock;
  late final int _openedAtMs;

  int _attempts = 0;
  String? _method;
  bool _success = false;
  String? _failureReason;
  int _fieldsFilled = 0;
  String? _existingPatient;
  bool _sent = false;

  bool get succeeded => _success;

  /// Current `existing_patient` value (null until a card was read).
  String? get existing => _existingPatient;

  /// One capture (camera) or picked photo (gallery) was read.
  void attempt({
    required String method,
    required bool success,
    String? failureReason,
    int fieldsFilled = 0,
  }) {
    _attempts++;
    _method = method;
    if (success) {
      _success = true;
      _failureReason = null;
      _fieldsFilled = fieldsFilled;
    } else if (!_success) {
      _failureReason = failureReason;
    }
  }

  /// Result of the "already registered?" lookup; null = could not check.
  void existingPatient(bool? found) =>
      _existingPatient = existingPatientValue(found);

  /// Sends `nid_scan_result` once; later calls are ignored.
  void finish() {
    if (_sent) return;
    _sent = true;
    final result = _success
        ? AnalyticsValue.success
        : _attempts > 0
            ? AnalyticsValue.failed
            : AnalyticsValue.cancelled;
    Analytics.event(AnalyticsEvent.nidScanResult, {
      AnalyticsParam.source: source,
      AnalyticsParam.result: result,
      AnalyticsParam.failureReason:
          result == AnalyticsValue.failed ? _failureReason : null,
      AnalyticsParam.method: _method,
      AnalyticsParam.attempts: _attempts,
      AnalyticsParam.fieldsFilled: _success ? _fieldsFilled : null,
      AnalyticsParam.existingPatient: _success ? _existingPatient : null,
      AnalyticsParam.scanMs: _clock() - _openedAtMs,
    });
  }
}

/// `enrollment_path_chosen` — what the SK picked in the home NID sheet.
void gaEnrollmentPathChosen({
  required String? source,
  required String action,
  String? existingPatient,
}) {
  Analytics.event(AnalyticsEvent.enrollmentPathChosen, {
    AnalyticsParam.source: source,
    AnalyticsParam.action: action,
    AnalyticsParam.existingPatient: existingPatient,
  });
}

Future<bool?> _online() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  } on Object catch (_) {
    return null;
  }
}

/// `household_created` — the new household was saved.
Future<void> gaHouseholdCreated({
  required String? source,
  required bool nidScan,
  required bool scanCleared,
  required String? type,
  required int members,
  required int formMs,
}) async {
  final online = await _online();
  Analytics.event(AnalyticsEvent.householdCreated, {
    AnalyticsParam.source: source,
    AnalyticsParam.nidScan: nidScan,
    AnalyticsParam.scanCleared: scanCleared,
    AnalyticsParam.type: type,
    AnalyticsParam.members: members,
    AnalyticsParam.isOnline: online,
    AnalyticsParam.formMs: formMs,
  });
}

/// `member_added` — a member was saved. (The head is registered by
/// `household_created`, so members added here are never the head.)
Future<void> gaMemberAdded({
  required String? source,
  required bool nidScan,
  required bool scanCleared,
  required int formMs,
}) async {
  final online = await _online();
  Analytics.event(AnalyticsEvent.memberAdded, {
    AnalyticsParam.source: source,
    AnalyticsParam.nidScan: nidScan,
    AnalyticsParam.scanCleared: scanCleared,
    AnalyticsParam.isOnline: online,
    AnalyticsParam.formMs: formMs,
  });
}
