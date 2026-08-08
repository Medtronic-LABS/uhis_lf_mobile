import 'package:flutter/services.dart';

import '../../../core/constants/app_strings.dart';

/// ID Type / National ID rules shared by the household-head form
/// ([CreateHouseholdScreen]) and the member form
/// ([AddHouseholdMemberScreen]).
///
/// Mirrors Spice `member_registration.json` plus the checks
/// `MemberRegistrationFragment.onFormSubmit` runs before saving:
///  * `id_type` (nid | brn | na) is mandatory.
///  * `national_id` is `visibility: gone` by default and only revealed for
///    nid/brn — while hidden it is skipped, so "Not Available" must not
///    demand a number.
///  * for nid the value must be digits only and 10, 13 or 17 characters long
///    (`MemberRegistration.NATIONAL_ID_LENGTH`), and typing is capped at 17
///    (`MAX_LENGTH_NATIONAL_ID`) on a numeric keyboard.
///  * brn keeps the plain text keyboard and has no length rule beyond being
///    filled in.
abstract final class EnrollmentIdNumber {
  static const String nationalId = 'National ID';
  static const String brn = 'BRN';
  static const String notAvailable = 'Not Available';

  static const List<int> nidLengths = [10, 13, 17];
  static const int nidMaxLength = 17;

  /// R.string.national_id_validation
  static String get nidFormatError => EnrollmentStrings.nidFormatError;

  /// R.string.national_id_already_exists
  static String get duplicateError => EnrollmentStrings.nidDuplicateAssignedError;

  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  /// Accepts both the display labels used by the forms ("National ID") and the
  /// short values stored on [HouseholdMember.idType] / sent to the server
  /// ("nid"), so callers on either side of that mapping behave the same.
  static String _normalize(String? idType) =>
      (idType ?? '').trim().toLowerCase().replaceAll(' ', '');

  /// Whether a number is collected at all — false for "Not Available", which
  /// hides the field in Spice.
  static bool isCollected(String? idType) {
    final s = _normalize(idType);
    return s.isNotEmpty && s != 'notavailable' && s != 'na';
  }

  static bool isNid(String? idType) {
    final s = _normalize(idType);
    return s == 'nationalid' || s == 'nid';
  }

  /// Field label follows the selected type, like Android's
  /// `FormGenerator.updateNationalIdLabelForIdType` (uses cultureValue).
  static String label(String? idType) => isNid(idType)
      ? EnrollmentStrings.nidNumberLabel
      : EnrollmentStrings.brnNumberLabel;

  static String hint(String? idType) => isNid(idType)
      ? EnrollmentStrings.nidNumberHint
      : EnrollmentStrings.brnNumberHint;

  static TextInputType keyboard(String? idType) =>
      isNid(idType) ? TextInputType.number : TextInputType.text;

  static List<TextInputFormatter> formatters(String? idType) => isNid(idType)
      ? [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(nidMaxLength),
        ]
      : const [];

  /// Validation message for [value] under [idType], or null when it passes.
  /// [requiredMessage] lets the inline field errors stay terse ("Required")
  /// while the controller reports a full sentence in its snackbar.
  static String? validate(
    String? idType,
    String? value, {
    String requiredMessage = 'Required',
  }) {
    if (!isCollected(idType)) return null;

    final v = value?.trim() ?? '';
    if (v.isEmpty) return requiredMessage;
    if (!isNid(idType)) return null;

    if (!_digitsOnly.hasMatch(v) || !nidLengths.contains(v.length)) {
      return nidFormatError;
    }
    return null;
  }
}
