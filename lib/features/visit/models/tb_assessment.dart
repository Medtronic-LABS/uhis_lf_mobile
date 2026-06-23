/// TB Assessment models matching spice-service TbDTO.
///
/// Contains TB screening (WHO 4-symptom screen) and contact tracing.
library;

/// TB screening section matching TBScreeningDTO.
///
/// Based on WHO 4-symptom TB screen:
/// - Cough (any duration)
/// - Cough ≥2 weeks
/// - Night sweats
/// - Fever
/// - Weight loss
class TbScreening {
  const TbScreening({
    this.hasCough,
    this.hasCoughLastedLonger,
    this.hasNightSweats,
    this.hasFever,
    this.hasWeightLoss,
    this.dateOfOnset,
  });

  final bool? hasCough;
  final bool? hasCoughLastedLonger; // ≥2 weeks
  final bool? hasNightSweats;
  final bool? hasFever;
  final bool? hasWeightLoss;
  final DateTime? dateOfOnset;

  /// WHO TB screening positive if ANY of the 4 symptoms are present.
  bool get isPositiveScreen =>
      hasCough == true ||
      hasNightSweats == true ||
      hasFever == true ||
      hasWeightLoss == true;

  /// Count of positive symptoms.
  int get symptomCount {
    int count = 0;
    if (hasCough == true) count++;
    if (hasNightSweats == true) count++;
    if (hasFever == true) count++;
    if (hasWeightLoss == true) count++;
    return count;
  }

  TbScreening copyWith({
    bool? hasCough,
    bool? hasCoughLastedLonger,
    bool? hasNightSweats,
    bool? hasFever,
    bool? hasWeightLoss,
    DateTime? dateOfOnset,
  }) =>
      TbScreening(
        hasCough: hasCough ?? this.hasCough,
        hasCoughLastedLonger: hasCoughLastedLonger ?? this.hasCoughLastedLonger,
        hasNightSweats: hasNightSweats ?? this.hasNightSweats,
        hasFever: hasFever ?? this.hasFever,
        hasWeightLoss: hasWeightLoss ?? this.hasWeightLoss,
        dateOfOnset: dateOfOnset ?? this.dateOfOnset,
      );

  Map<String, dynamic> toJson() => {
        if (hasCough != null) 'hasCough': hasCough,
        if (hasCoughLastedLonger != null)
          'hasCoughLastedLonger': hasCoughLastedLonger,
        if (hasNightSweats != null) 'hasNightSweats': hasNightSweats,
        if (hasFever != null) 'hasFever': hasFever,
        if (hasWeightLoss != null) 'hasWeightLoss': hasWeightLoss,
        if (dateOfOnset != null) 'dateOfOnset': dateOfOnset!.toIso8601String(),
      };

  factory TbScreening.fromJson(Map<String, dynamic> json) => TbScreening(
        hasCough: json['hasCough'] as bool?,
        hasCoughLastedLonger: json['hasCoughLastedLonger'] as bool?,
        hasNightSweats: json['hasNightSweats'] as bool?,
        hasFever: json['hasFever'] as bool?,
        hasWeightLoss: json['hasWeightLoss'] as bool?,
        dateOfOnset: json['dateOfOnset'] != null
            ? DateTime.parse(json['dateOfOnset'] as String)
            : null,
      );
}

/// Contact tracing section matching ContactTracingDTO.
class ContactTracing {
  const ContactTracing({
    this.relationshipToIC,
    this.otherRelationshipIC,
    this.sleepLocation,
    this.hasPreviouslyTreatedForTB,
  });

  /// Relationship to index case.
  final String? relationshipToIC;

  /// Other relationship description if "other" selected.
  final String? otherRelationshipIC;

  /// Where the contact sleeps (same room, different room, etc.)
  final String? sleepLocation;

  /// Whether previously treated for TB.
  final bool? hasPreviouslyTreatedForTB;

  ContactTracing copyWith({
    String? relationshipToIC,
    String? otherRelationshipIC,
    String? sleepLocation,
    bool? hasPreviouslyTreatedForTB,
  }) =>
      ContactTracing(
        relationshipToIC: relationshipToIC ?? this.relationshipToIC,
        otherRelationshipIC: otherRelationshipIC ?? this.otherRelationshipIC,
        sleepLocation: sleepLocation ?? this.sleepLocation,
        hasPreviouslyTreatedForTB:
            hasPreviouslyTreatedForTB ?? this.hasPreviouslyTreatedForTB,
      );

  Map<String, dynamic> toJson() => {
        if (relationshipToIC != null) 'relationshipToIC': relationshipToIC,
        if (otherRelationshipIC != null)
          'otherRelationshipIC': otherRelationshipIC,
        if (sleepLocation != null) 'sleepLocation': sleepLocation,
        if (hasPreviouslyTreatedForTB != null)
          'hasPreviouslyTreatedForTB': hasPreviouslyTreatedForTB,
      };

  factory ContactTracing.fromJson(Map<String, dynamic> json) => ContactTracing(
        relationshipToIC: json['relationshipToIC'] as String?,
        otherRelationshipIC: json['otherRelationshipIC'] as String?,
        sleepLocation: json['sleepLocation'] as String?,
        hasPreviouslyTreatedForTB: json['hasPreviouslyTreatedForTB'] as bool?,
      );
}

/// Complete TB assessment matching spice-service TbDTO.
class TbAssessment {
  const TbAssessment({
    this.tbScreening,
    this.contactTracing,
  });

  final TbScreening? tbScreening;
  final ContactTracing? contactTracing;

  /// Whether this assessment indicates a positive TB screen.
  bool get isPositive => tbScreening?.isPositiveScreen ?? false;

  /// Whether referral is recommended based on screening.
  bool get referralRecommended => isPositive;

  TbAssessment copyWith({
    TbScreening? tbScreening,
    ContactTracing? contactTracing,
  }) =>
      TbAssessment(
        tbScreening: tbScreening ?? this.tbScreening,
        contactTracing: contactTracing ?? this.contactTracing,
      );

  Map<String, dynamic> toJson() => {
        if (tbScreening != null) 'tbScreening': tbScreening!.toJson(),
        if (contactTracing != null) 'contactTracing': contactTracing!.toJson(),
      };

  factory TbAssessment.fromJson(Map<String, dynamic> json) => TbAssessment(
        tbScreening: json['tbScreening'] != null
            ? TbScreening.fromJson(json['tbScreening'] as Map<String, dynamic>)
            : null,
        contactTracing: json['contactTracing'] != null
            ? ContactTracing.fromJson(
                json['contactTracing'] as Map<String, dynamic>)
            : null,
      );
}

/// Relationship options for contact tracing.
class TbRelationshipOptions {
  static const List<String> values = [
    'Parent',
    'Child',
    'Sibling',
    'Spouse',
    'Grandparent',
    'Grandchild',
    'Other relative',
    'Non-relative household member',
    'Other',
  ];
}

/// Sleep location options for contact tracing.
class TbSleepLocationOptions {
  static const List<String> values = [
    'Same room as index case',
    'Different room, same house',
    'Different house',
  ];
}
