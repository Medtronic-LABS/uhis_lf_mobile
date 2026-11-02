import '../../core/constants/app_strings.dart';

/// UHIS [ServiceStaticFilter] — service-recipient cohorts on the Members screen.
enum ServiceStaticFilter {
  allMembers,
  externalMembers,
  childrenUnderTwo,
  pregnantWomen,
  externalPregnantWomen,
  highRiskPregnantWomen,
  familyPlanningCounselling,
  postnatalCareMothers,
  expectedDeliveries,
  pendingDeliveries,
  ncdServices,
  cataractScreening,
  eyeScreening,
  otherServices;

  /// Members screen dropdown (Leapfrog SK — no external / communicable cohorts).
  static List<ServiceStaticFilter> allowedForSk() => const [
        ServiceStaticFilter.allMembers,
        ServiceStaticFilter.childrenUnderTwo,
        ServiceStaticFilter.pregnantWomen,
        ServiceStaticFilter.highRiskPregnantWomen,
        ServiceStaticFilter.familyPlanningCounselling,
        ServiceStaticFilter.postnatalCareMothers,
        ServiceStaticFilter.expectedDeliveries,
        ServiceStaticFilter.pendingDeliveries,
        ServiceStaticFilter.ncdServices,
        ServiceStaticFilter.eyeScreening,
      ];

  /// FO/PO service list (no RMNCH cohorts; includes cataract).
  static List<ServiceStaticFilter> allowedForFoPo() => const [
        ServiceStaticFilter.allMembers,
        ServiceStaticFilter.ncdServices,
        ServiceStaticFilter.cataractScreening,
        ServiceStaticFilter.eyeScreening,
      ];
}

extension ServiceStaticFilterLabels on ServiceStaticFilter {
  String get label => switch (this) {
        ServiceStaticFilter.allMembers =>
          ServiceMemberFilterStrings.allMembers,
        ServiceStaticFilter.externalMembers =>
          ServiceMemberFilterStrings.externalMembers,
        ServiceStaticFilter.childrenUnderTwo =>
          ServiceMemberFilterStrings.childrenUnderTwo,
        ServiceStaticFilter.pregnantWomen =>
          ServiceMemberFilterStrings.pregnantWomen,
        ServiceStaticFilter.externalPregnantWomen =>
          ServiceMemberFilterStrings.externalPregnantWomen,
        ServiceStaticFilter.highRiskPregnantWomen =>
          ServiceMemberFilterStrings.highRiskPregnantWomen,
        ServiceStaticFilter.familyPlanningCounselling =>
          ServiceMemberFilterStrings.familyPlanningCounselling,
        ServiceStaticFilter.postnatalCareMothers =>
          ServiceMemberFilterStrings.postnatalCareMothers,
        ServiceStaticFilter.expectedDeliveries =>
          ServiceMemberFilterStrings.expectedDeliveries,
        ServiceStaticFilter.pendingDeliveries =>
          ServiceMemberFilterStrings.pendingDeliveries,
        ServiceStaticFilter.ncdServices => ServiceMemberFilterStrings.ncdServices,
        ServiceStaticFilter.cataractScreening =>
          ServiceMemberFilterStrings.cataractScreening,
        ServiceStaticFilter.eyeScreening =>
          ServiceMemberFilterStrings.eyeScreening,
        ServiceStaticFilter.otherServices =>
          ServiceMemberFilterStrings.otherServices,
      };
}
