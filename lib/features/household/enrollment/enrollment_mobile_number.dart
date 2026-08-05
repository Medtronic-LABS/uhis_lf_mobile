import 'package:flutter/services.dart';

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
  static const String startsWithError =
      'Phone number should starts with $requiredPrefix';

  /// Length mismatch vs Android `phoneNumberContainMaxLength` (exact).
  static const String lengthError = 'Mobile number must be $maxLength digits';

  /// R.string.phone_number_invalid
  static const String invalidError = 'Please enter a valid mobile number';

  static final RegExp _digitsOnly = RegExp(r'^\d+$');
  static final RegExp _fiveSameDigits = RegExp(r'(\d)\1{4}');

  static List<TextInputFormatter> get formatters => [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(maxLength),
      ];

  /// Returns an error message, or null when valid.
  ///
  /// When [required] is false, empty input is allowed (member forms). When
  /// true, empty fails with [requiredMessage] (household head).
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
