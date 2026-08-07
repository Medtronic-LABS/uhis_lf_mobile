import 'package:flutter/services.dart';

import '../../../core/constants/app_strings.dart';

/// Mobile-number rules shared by household-head and member enrollment forms.
///
/// Mirrors Spice `member_registration.json` + `FormGenerator` checks:
///  * `optionType`: phoneNumberWithoutCountryCode
///  * `maxLength`: 11 (exact length required)
///  * `startsWith`: ["01"]
///  * reject 5+ consecutive identical digits (`FormFieldValidator`)
abstract final class EnrollmentMobileNumber {
  static const int maxLength = 11;
  static const String requiredPrefix = '01';

  /// R.string.start_with_validation with %1$s = "01"
  static String get startsWithError =>
      EnrollmentStrings.mobileStartsWithError(requiredPrefix);

  /// Length mismatch vs Android `phoneNumberContainMaxLength` (exact).
  static String get lengthError => EnrollmentStrings.mobileLengthError(maxLength);

  /// R.string.phone_number_invalid
  static String get invalidError => EnrollmentStrings.mobileInvalidError;

  static final RegExp _digitsOnly = RegExp(r'^\d+$');
  static final RegExp _fiveSameDigits = RegExp(r'(\d)\1{4}');

  static List<TextInputFormatter> get formatters => [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(maxLength),
      ];

  /// Returns an error message, or null when valid.
  ///
  /// When [required] is false, empty input is allowed. When true (household
  /// head and add-member — Spice `isMandatory: true`), empty fails with
  /// [requiredMessage].
  static String? validate(
    String? value, {
    bool required = false,
    String requiredMessage = 'Required',
  }) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return required ? requiredMessage : null;
    }

    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (!_digitsOnly.hasMatch(digits)) {
      return invalidError;
    }
    if (!digits.startsWith(requiredPrefix)) {
      return startsWithError;
    }
    if (digits.length != maxLength) {
      return lengthError;
    }
    if (_fiveSameDigits.hasMatch(digits)) {
      return invalidError;
    }
    return null;
  }
}
