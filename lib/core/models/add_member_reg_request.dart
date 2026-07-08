import 'provance_dto.dart';

/// Request DTO for POST /spice-service/household/create-member
/// Matches Android's AddMemberRegRequest exactly.
class AddMemberRegRequest {
  String? dateOfBirth;
  String? gender;
  int? householdId;
  String? name;
  String? patientId;
  int? motherPatientId;
  bool? child;
  bool? isPregnant;
  String? phoneNumber;
  String? phoneNumberCategory;
  ProvanceDto? provenance;
  String? village;
  String? villageId;
  double latitude;
  double longitude;

  AddMemberRegRequest({
    this.dateOfBirth,
    this.gender,
    this.householdId,
    this.name,
    this.patientId,
    this.motherPatientId,
    this.child,
    this.isPregnant,
    this.phoneNumber,
    this.phoneNumberCategory,
    this.provenance,
    this.village,
    this.villageId,
    this.latitude = 0.0,
    this.longitude = 0.0,
  });

  /// Convert to JSON for API requests.
  Map<String, dynamic> toJson() => {
    'dateOfBirth': dateOfBirth,
    'gender': gender,
    'householdId': householdId,
    'name': name,
    'patientId': patientId,
    'motherPatientId': motherPatientId,
    'child': child,
    'isPregnant': isPregnant,
    'phoneNumber': phoneNumber,
    'phoneNumberCategory': phoneNumberCategory,
    'provenance': provenance?.toJson(),
    'village': village,
    'villageId': villageId,
    'latitude': latitude,
    'longitude': longitude,
  };

  @override
  String toString() => 'AddMemberRegRequest(name=$name, householdId=$householdId, villageId=$villageId)';
}
