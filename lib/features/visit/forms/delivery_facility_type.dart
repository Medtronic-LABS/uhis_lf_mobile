import '../../../core/constants/app_strings.dart';
import 'form_config.dart';

/// ANC delivery-facility spinner options (`facilityIdentifiedForDelivery` /
/// `deliveryFacilityType` in `field_library.json`).
///
/// Wire payloads store the option **id** (e.g. `ngoFacility`); UI labels
/// resolve via [labelOfId] → `VisitFlow.deliveryFacilityType.*` translations.
abstract final class DeliveryFacilityType {
  DeliveryFacilityType._();

  static const List<FieldOption> options = [
    FieldOption(
      id: 'uhfwc',
      name: 'UHFWC (Union health and family welfare center)',
      cultureValue: 'ইউনিয়ন স্বাস্থ্য ও পরিবার কল্যাণ কেন্দ্র',
    ),
    FieldOption(
      id: 'mcwc',
      name: 'MCWC (Mother and Child Welfare Center)',
      cultureValue: 'মা ও শিশু কল্যাণ কেন্দ্র',
    ),
    FieldOption(
      id: 'uhc',
      name: 'UHC (Upazila Health complex)',
      cultureValue: 'উপজেলা স্বাস্থ্য কমপ্লেক্স',
    ),
    FieldOption(
      id: 'districtHospital',
      name: 'District Hospital',
      cultureValue: 'জেলা হাসপাতাল',
    ),
    FieldOption(
      id: 'medicalCollegeHospital',
      name: 'Medical College Hospital',
      cultureValue: 'মেডিকেল কলেজ হাসপাতাল',
    ),
    FieldOption(
      id: 'ngoFacility',
      name: 'NGO facility',
      cultureValue: 'এনজিও স্বাস্থ্যসেবা কেন্দ্র',
    ),
    FieldOption(
      id: 'privateFacility',
      name: 'Private Facility',
      cultureValue: 'প্রাইভেট হাসপাতাল',
    ),
    FieldOption(
      id: 'notIdentified',
      name: 'Not identified yet',
      cultureValue: 'এখনও ঠিক হয়নি',
    ),
    FieldOption(
      id: 'homeDelivery',
      name: 'Planned for home delivery',
      cultureValue: 'ঘরে প্রসবের পরিকল্পনা করা হয়েছে',
    ),
  ];

  static String labelOf(FieldOption option) => getTranslatedString(
        'VisitFlow.deliveryFacilityType.${option.id}',
        option.displayName,
      );

  /// Maps a stored wire id (or legacy label) to a locale-aware display label.
  static String labelOfId(String wireId) {
    final option = FieldOption.find(wireId, options);
    if (option != null) return labelOf(option);
    return wireId;
  }
}
