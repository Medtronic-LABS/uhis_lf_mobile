/// Data models for household enrollment flow.
///
/// Plain Dart classes (no Freezed/Equatable). Mutable during form input;
/// immutable after submission to local DB.
library;

class HouseholdMember {
  HouseholdMember({
    this.id,
    required this.name,
    this.fatherName,
    this.motherName,
    required this.age,
    required this.gender,
    required this.dateOfBirth,
    required this.idType,
    this.idNumber,
    this.mobileNumber,
    this.mobileAvailable = true,
    required this.maritalStatus,
    required this.disabilityStatus,
    required this.relationshipToHead,
    this.villageId,
    this.nidScanned = false,
  });

  final String? id;
  final String name;

  /// Father's name — printed in Bangla on the NID, so entered manually.
  final String? fatherName;

  /// Mother's name — printed in Bangla on the NID, so entered manually.
  final String? motherName;
  final int age;
  final String gender; // 'Male', 'Female', 'Other'
  final String dateOfBirth; // ISO 8601 string (YYYY-MM-DD)
  final String idType; // 'BRN', 'NID'
  final String? idNumber;
  final String? mobileNumber;
  final bool mobileAvailable;
  final String maritalStatus; // 'Single', 'Married', 'Widowed', 'Divorced'
  final String disabilityStatus; // 'None', 'Physical', 'Sensory', 'Cognitive', 'Multiple'
  final String relationshipToHead; // 'Head', 'Spouse', 'Child', 'Parent', 'Sibling', 'Other'
  final String? villageId; // Only for external members
  final bool nidScanned;

  HouseholdMember copyWith({
    String? id,
    String? name,
    String? fatherName,
    String? motherName,
    int? age,
    String? gender,
    String? dateOfBirth,
    String? idType,
    String? idNumber,
    String? mobileNumber,
    bool? mobileAvailable,
    String? maritalStatus,
    String? disabilityStatus,
    String? relationshipToHead,
    String? villageId,
    bool? nidScanned,
  }) {
    return HouseholdMember(
      id: id ?? this.id,
      name: name ?? this.name,
      fatherName: fatherName ?? this.fatherName,
      motherName: motherName ?? this.motherName,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      idType: idType ?? this.idType,
      idNumber: idNumber ?? this.idNumber,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      mobileAvailable: mobileAvailable ?? this.mobileAvailable,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      disabilityStatus: disabilityStatus ?? this.disabilityStatus,
      relationshipToHead: relationshipToHead ?? this.relationshipToHead,
      villageId: villageId ?? this.villageId,
      nidScanned: nidScanned ?? this.nidScanned,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'fatherName': fatherName,
      'motherName': motherName,
      'age': age,
      'gender': gender,
      'dateOfBirth': dateOfBirth,
      'idType': idType,
      'idNumber': idNumber,
      'mobileNumber': mobileNumber,
      'mobileAvailable': mobileAvailable,
      'maritalStatus': maritalStatus,
      'disabilityStatus': disabilityStatus,
      'relationshipToHead': relationshipToHead,
      'villageId': villageId,
      'nidScanned': nidScanned,
    };
  }

  static HouseholdMember fromJson(Map<String, dynamic> json) {
    return HouseholdMember(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      fatherName: json['fatherName'] as String?,
      motherName: json['motherName'] as String?,
      age: json['age'] as int? ?? 0,
      gender: json['gender'] as String? ?? 'Other',
      dateOfBirth: json['dateOfBirth'] as String? ?? '',
      idType: json['idType'] as String? ?? 'NID',
      idNumber: json['idNumber'] as String?,
      mobileNumber: json['mobileNumber'] as String?,
      mobileAvailable: json['mobileAvailable'] as bool? ?? true,
      maritalStatus: json['maritalStatus'] as String? ?? 'Single',
      disabilityStatus: json['disabilityStatus'] as String? ?? 'None',
      relationshipToHead: json['relationshipToHead'] as String? ?? 'Other',
      villageId: json['villageId'] as String?,
      nidScanned: json['nidScanned'] as bool? ?? false,
    );
  }
}

class HouseholdHeadInfo extends HouseholdMember {
  HouseholdHeadInfo({
    required super.name,
    super.fatherName,
    super.motherName,
    required super.age,
    required super.gender,
    required super.dateOfBirth,
    required super.idType,
    super.idNumber,
    super.mobileNumber,
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
    String? fatherName,
    String? motherName,
    int? age,
    String? gender,
    String? dateOfBirth,
    String? idType,
    String? idNumber,
    String? mobileNumber,
    bool? mobileAvailable,
    String? maritalStatus,
    String? disabilityStatus,
    String? relationshipToHead,
    String? villageId,
    bool? nidScanned,
  }) {
    return HouseholdHeadInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      fatherName: fatherName ?? this.fatherName,
      motherName: motherName ?? this.motherName,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      idType: idType ?? this.idType,
      idNumber: idNumber ?? this.idNumber,
      mobileNumber: mobileNumber ?? this.mobileNumber,
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
    required this.monthlyIncome,
    required this.disabilityQuestion,
    this.disabilityDetails,
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
  final String houseNumber;
  final String occupation;
  final String monthlyIncome; // '<10000', '10000-25000', '25000-50000', '>50000'
  final bool disabilityQuestion; // Does household have member with disability?
  final String? disabilityDetails; // If disabilityQuestion is true
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
    String? monthlyIncome,
    bool? disabilityQuestion,
    String? disabilityDetails,
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
      monthlyIncome: monthlyIncome ?? this.monthlyIncome,
      disabilityQuestion: disabilityQuestion ?? this.disabilityQuestion,
      disabilityDetails: disabilityDetails ?? this.disabilityDetails,
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
      'monthlyIncome': monthlyIncome,
      'disabilityQuestion': disabilityQuestion,
      'disabilityDetails': disabilityDetails,
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
      monthlyIncome: json['monthlyIncome'] as String? ?? '<10000',
      disabilityQuestion: json['disabilityQuestion'] as bool? ?? false,
      disabilityDetails: json['disabilityDetails'] as String?,
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] is String
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }
}
