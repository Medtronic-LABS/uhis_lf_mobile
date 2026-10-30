/// Plain `{{token}}` substitution against the fetched consent HTML, for live on-screen
/// display only -- purely cosmetic, so the patient reads their own name/CHW name/date
/// instead of literal blanks while deciding. The backend independently re-renders the
/// same token convention server-side into `Shukhee Consent Log.filled_consent` at the
/// moment the decision is recorded, from server-resolved values only -- that one is the
/// tamper-resistant audit copy; this one only has to work instantly, offline-friendly,
/// before any decision exists to record.
String fillConsentTemplate(
  String html, {
  required String participantName,
  required String participantId,
  required DateTime dateTime,
  required String lng,
  String? chwName,
  String? consentVersion,
}) {
  final tokens = <String, String>{
    'participant_name': participantName,
    'participant_id': participantId,
    'date_time': _formatDateTime(dateTime),
    'language': lng == 'bn' ? 'বাংলা' : 'English',
    'chw_name': chwName ?? '',
    'consent_version': consentVersion ?? '',
    'consent_method': lng == 'bn' ? 'অ্যাপ' : 'App',
  };

  var filled = html;
  for (final entry in tokens.entries) {
    filled = filled.replaceAll('{{${entry.key}}}', entry.value);
  }
  return filled;
}

String _formatDateTime(DateTime dateTime) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dateTime.year}-${two(dateTime.month)}-${two(dateTime.day)} '
      '${two(dateTime.hour)}:${two(dateTime.minute)}';
}
