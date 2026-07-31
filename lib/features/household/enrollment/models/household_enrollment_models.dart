/// Data models for household enrollment flow.
///
/// Plain Dart classes (no Freezed/Equatable). Mutable during form input;
/// immutable after submission to local DB.
library;

class HouseholdMember {
  HouseholdMember({
    this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.dateOfBirth,
    required this.idType,
    this.idNumber,
    this.mobileNumber,
    this.phoneNumberCategory,
    this.mobileAvailable = true,
    required this.maritalStatus,
    required this.disabilityStatus,
    required this.relationshipToHead,
    this.villageId,
    this.nidScanned = false,
    this.guardianName,
  });

  final String? id;
  final String name;
  final int age;
  final String gender; // 'Male', 'Female', 'Other'
  final String dateOfBirth; // ISO 8601 string (YYYY-MM-DD)
  final String idType; // 'BRN', 'NID'
  final String? idNumber;
  final String? mobileNumber;

  /// Spice `phone_number_category` display label; see
  /// [EnrollmentStrings.phoneCategoryIds] for the wire ids.
  final String? phoneNumberCategory;
  final bool mobileAvailable;
  final String maritalStatus; // 'Single', 'Married', 'Unmarried'
  final String disabilityStatus;
  final String relationshipToHead; // 'Head', 'Spouse', 'Child', 'Parent', 'Sibling', 'Other'
  final String? villageId; // Only for external members
  final bool nidScanned;
  final String? guardianName;

  HouseholdMember copyWith({
    String? id,
    String? name,
    int? age,
    String? gender,
    String? dateOfBirth,
    String? idType,
    String? idNumber,
    String? mobileNumber,
    String? phoneNumberCategory,
    bool? mobileAvailable,
    String? maritalStatus,
    String? disabilityStatus,
    String? relationshipToHead,
    String? villageId,
    bool? nidScanned,
    String? guardianName,
  }) {
    return HouseholdMember(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      idType: idType ?? this.idType,
      idNumber: idNumber ?? this.idNumber,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      phoneNumberCategory: phoneNumberCategory ?? this.phoneNumberCategory,
      mobileAvailable: mobileAvailable ?? this.mobileAvailable,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      disabilityStatus: disabilityStatus ?? this.disabilityStatus,
      relationshipToHead: relationshipToHead ?? this.relationshipToHead,
      villageId: villageId ?? this.villageId,
      nidScanned: nidScanned ?? this.nidScanned,
      guardianName: guardianName ?? this.guardianName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'gender': gender,
      'dateOfBirth': dateOfBirth,
      'idType': idType,
      'idNumber': idNumber,
      'mobileNumber': mobileNumber,
      'phoneNumberCategory': phoneNumberCategory,
      'mobileAvailable': mobileAvailable,
      'maritalStatus': maritalStatus,
      'disabilityStatus': disabilityStatus,
      'relationshipToHead': relationshipToHead,
      'villageId': villageId,
      'nidScanned': nidScanned,
      'guardianName': guardianName,
    };
  }

  static HouseholdMember fromJson(Map<String, dynamic> json) {
    return HouseholdMember(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      age: json['age'] as int? ?? 0,
      gender: json['gender'] as String? ?? 'Other',
      dateOfBirth: json['dateOfBirth'] as String? ?? '',
      idType: json['idType'] as String? ?? 'NID',
      idNumber: json['idNumber'] as String?,
      mobileNumber: json['mobileNumber'] as String?,
      phoneNumberCategory: json['phoneNumberCategory'] as String?,
      mobileAvailable: json['mobileAvailable'] as bool? ?? true,
      maritalStatus: json['maritalStatus'] as String? ?? 'Single',
      disabilityStatus: json['disabilityStatus'] as String? ?? 'None',
      relationshipToHead: json['relationshipToHead'] as String? ?? 'Other',
      villageId: json['villageId'] as String?,
      nidScanned: json['nidScanned'] as bool? ?? false,
      guardianName: json['guardianName'] as String?,
    );
  }
}

class HouseholdHeadInfo extends HouseholdMember {
  HouseholdHeadInfo({
    required super.name,
    required super.age,
    required super.gender,
    required super.dateOfBirth,
    required super.idType,
    super.idNumber,
    super.mobileNumber,
    super.phoneNumberCategory,
    super.mobileAvailable,
    required super.maritalStatus,
    required super.disabilityStatus,
    super.villageId,
    super.nidScanned,
    super.id,
  }) : super(relationshipToHead: 'Head');

  @override
  HouseholdHeadInfo copyWith({
    String? id,
    String? name,
    int? age,
    String? gender,
    String? dateOfBirth,
    String? idType,
    String? idNumber,
    String? mobileNumber,
    String? phoneNumberCategory,
    bool? mobileAvailable,
    String? maritalStatus,
    String? disabilityStatus,
    String? relationshipToHead,
    String? villageId,
    bool? nidScanned,
    String? guardianName,
  }) {
    return HouseholdHeadInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      idType: idType ?? this.idType,
      idNumber: idNumber ?? this.idNumber,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      phoneNumberCategory: phoneNumberCategory ?? this.phoneNumberCategory,
      mobileAvailable: mobileAvailable ?? this.mobileAvailable,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      disabilityStatus: disabilityStatus ?? this.disabilityStatus,
      villageId: villageId ?? this.villageId,
      nidScanned: nidScanned ?? this.nidScanned,
    );
  }
}

class Household {
  Household({
    required this.householdNumber,
    required this.healthWorkerId,
    required this.villageId,
    this.villageName,
    this.subVillageId,
    this.subVillageName,
    required this.householdType,
    required this.numberOfMembers,
    required this.houseNumber,
    required this.occupation,
    this.otherOccupation = '',
    required this.monthlyIncomeRange,
    this.disabilityPersonsCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String householdNumber;
  final String healthWorkerId;
  final String villageId;
  final String? villageName;
  final String? subVillageId;
  final String? subVillageName;
  final String householdType; // 'Single-family', 'Multi-family', 'Institutional', 'Other'
  final int numberOfMembers;

  /// Not collected anywhere: Spice asks for a house/road number only on the NCD
  /// `registration.json` patient form, never on household or member
  /// registration. Kept so previously persisted drafts still deserialize.
  final String houseNumber;

  /// Spice `householdHeadOccupation` option id (EnrollmentStrings.occupationOptions).
  final String occupation;

  /// Spice `otherOccupation` free text; only meaningful when [occupation] is 'Other'.
  final String otherOccupation;

  /// Spice `monthlyIncomeRange` option id, e.g. '<5000', '5001–10000'.
  final String monthlyIncomeRange;
  final int disabilityPersonsCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Household copyWith({
    String? householdNumber,
    String? healthWorkerId,
    String? villageId,
    String? villageName,
    String? subVillageId,
    String? subVillageName,
    String? householdType,
    int? numberOfMembers,
    String? houseNumber,
    String? occupation,
    String? otherOccupation,
    String? monthlyIncomeRange,
    int? disabilityPersonsCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Household(
      householdNumber: householdNumber ?? this.householdNumber,
      healthWorkerId: healthWorkerId ?? this.healthWorkerId,
      villageId: villageId ?? this.villageId,
      villageName: villageName ?? this.villageName,
      subVillageId: subVillageId ?? this.subVillageId,
      subVillageName: subVillageName ?? this.subVillageName,
      householdType: householdType ?? this.householdType,
      numberOfMembers: numberOfMembers ?? this.numberOfMembers,
      houseNumber: houseNumber ?? this.houseNumber,
      occupation: occupation ?? this.occupation,
      otherOccupation: otherOccupation ?? this.otherOccupation,
      monthlyIncomeRange: monthlyIncomeRange ?? this.monthlyIncomeRange,
      disabilityPersonsCount:
          disabilityPersonsCount ?? this.disabilityPersonsCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'householdNumber': householdNumber,
      'healthWorkerId': healthWorkerId,
      'villageId': villageId,
      'villageName': villageName,
      'subVillageId': subVillageId,
      'subVillageName': subVillageName,
      'householdType': householdType,
      'numberOfMembers': numberOfMembers,
      'houseNumber': houseNumber,
      'occupation': occupation,
      'otherOccupation': otherOccupation,
      'monthlyIncomeRange': monthlyIncomeRange,
      'disabilityPersonsCount': disabilityPersonsCount,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  static Household fromJson(Map<String, dynamic> json) {
    return Household(
      householdNumber: json['householdNumber'] as String? ?? '',
      healthWorkerId: json['healthWorkerId'] as String? ?? '',
      villageId: json['villageId'] as String? ?? '',
      villageName: json['villageName'] as String?,
      subVillageId: json['subVillageId'] as String?,
      subVillageName: json['subVillageName'] as String?,
      householdType: json['householdType'] as String? ?? 'Single-family',
      numberOfMembers: json['numberOfMembers'] as int? ?? 0,
      houseNumber: json['houseNumber'] as String? ?? '',
      occupation: json['occupation'] as String? ?? '',
      otherOccupation: json['otherOccupation'] as String? ?? '',
      monthlyIncomeRange: json['monthlyIncomeRange'] as String? ?? '',
      disabilityPersonsCount: json['disabilityPersonsCount'] as int? ?? 0,
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] is String
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }
}
