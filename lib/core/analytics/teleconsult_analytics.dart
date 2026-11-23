import 'package:shukhee_sdk/shukhee_sdk.dart';

import 'analytics_events.dart';

/// GA (LEAP-152) helpers for the Shukhee "Call doctor" teleconsult flow.
/// Pure functions so the mapping is unit-tested; the screen sends the events.
/// Never sent: patient name, contact number, reason text, doctor name,
/// Shukhee/Call Log ids or document content.

/// Same number ignoring formatting and the `88` country prefix.
bool sameBdMobile(String? a, String? b) {
  String norm(String? v) {
    final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
    return d.startsWith('88') && d.length == 13 ? d.substring(2) : d;
  }

  final na = norm(a);
  return na.isNotEmpty && na == norm(b);
}

/// GA `failure_reason` for a Shukhee booking / specialities error. Matches the
/// backend's own messages (shukhee_integration consultation.py /
/// shukhee_client.py) so the categories stay stable across languages.
String teleconsultFailureReason(Object error) {
  if (error is ShukheeNotProvisionedException) {
    return _msg(error).contains('inactive')
        ? AnalyticsValue.accountInactive
        : AnalyticsValue.notProvisioned;
  }
  if (error is ShukheeUnauthorizedException) return AnalyticsValue.unauthorized;
  final m = _msg(error);
  if (m.contains('mobile number')) return AnalyticsValue.invalidMobile;
  if (m.contains('inactive')) return AnalyticsValue.accountInactive;
  if (m.contains('could not reach shukhee')) return AnalyticsValue.vendorUnreachable;
  if (m.contains('shukhee patient')) return AnalyticsValue.patientNotResolved;
  if (m.contains('booking the shukhee') || m.contains('request id')) {
    return AnalyticsValue.bookingFailed;
  }
  if (m.contains('socketexception') ||
      m.contains('connection') ||
      m.contains('timed out') ||
      m.contains('timeout')) {
    return AnalyticsValue.offline;
  }
  if (m.contains('required')) return AnalyticsValue.validation;
  return AnalyticsValue.other;
}

String _msg(Object e) =>
    (e is ShukheeException ? e.message : e.toString()).toLowerCase();

/// GA `status` for `teleconsult_call_ended`: Shukhee's final status, or
/// `timeout` when polling gave up before the call reached one.
String teleconsultEndStatus(ShukheeStatus? status) =>
    status != null && status.isTerminal ? status.status : AnalyticsValue.timeout;
