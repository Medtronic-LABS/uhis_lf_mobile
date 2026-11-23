import 'package:shukhee_sdk/shukhee_sdk.dart';

/// Bangladeshi mobile numbers for the teleconsult booking form.
///
/// Shukhee's backend only accepts an 11-digit BD mobile (`01[3-9]` + 8
/// digits) and rejects anything else with "Invalid Bangladeshi mobile
/// number", which creates no booking. Checking it on the form gives the SK a
/// clear message instead of a failed call.

final _formatting = RegExp(r'[\s-]');
final _bdMobile = RegExp(r'^(?:\+?88)?01[3-9]\d{8}$');

/// [input] without spaces and dashes, as sent to the backend.
String normalizeBdMobile(String input) =>
    input.trim().replaceAll(_formatting, '');

/// True for `01712345678`, `+8801712345678`, `8801712345678`, and the same
/// written with spaces or dashes.
bool isValidBdMobile(String input) => _bdMobile.hasMatch(normalizeBdMobile(input));

/// True when the backend rejected the booking's contact number. The SDK's
/// exceptions only carry the backend message, so this matches its wording.
bool isInvalidMobileError(ShukheeException error) =>
    error.message.toLowerCase().contains('mobile number');
