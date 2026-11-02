import 'nid_ocr_service.dart';

/// Builds GoRouter `extra` for [/household/enrollment/link-member] from data
/// already on the household roster — no SQLite round-trip before [push].
Map<String, dynamic> buildLinkMemberRouteExtra({
  required String localHouseholdId,
  String? householdFhirId,
  required String householdName,
  required String householdNo,
  required String villageName,
  required String villageId,
  required String subVillageId,
  required String subVillageName,
  required List<String> memberNames,
  required String headName,
  required String headPhoneNumber,
  required NidScanResult scanResult,
}) {
  final trimmedFhir = householdFhirId?.trim();
  final serverHouseholdId = trimmedFhir != null && trimmedFhir.isNotEmpty
      ? trimmedFhir
      : localHouseholdId;

  final extra = <String, dynamic>{
    'householdId': serverHouseholdId,
    'householdReferenceId': localHouseholdId,
    'householdName': householdName,
    'householdNo': householdNo,
    'headName': headName,
    'headPhoneNumber': headPhoneNumber,
    'villageId': villageId,
    'villageName': villageName,
    'subVillageId': subVillageId,
    'subVillageName': subVillageName,
    'memberNames': memberNames,
  };

  if (scanResult.status == NidScanStatus.success && scanResult.data != null) {
    final data = scanResult.data!;
    extra['fromNidScan'] = true;
    extra['nidNumber'] = data.nidNumber;
    extra['name'] = data.name;
    extra['dateOfBirth'] = data.dateOfBirth;
    final genderLabel = data.gender?.label;
    if (genderLabel != null && genderLabel.isNotEmpty) {
      extra['gender'] = genderLabel;
    }
  }
  return extra;
}
