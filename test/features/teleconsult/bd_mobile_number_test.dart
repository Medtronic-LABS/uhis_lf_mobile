import 'package:flutter_test/flutter_test.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';
import 'package:uhis_next/features/teleconsult/bd_mobile_number.dart';

void main() {
  test('accepts 11-digit BD mobiles, with or without 88 / +88', () {
    for (final n in [
      '01712345678', '01312345678', '8801912345678', '+8801512345678',
      '017-1234-5678', '017 1234 5678', ' 01712345678 ',
    ]) {
      expect(isValidBdMobile(n), isTrue, reason: n);
    }
  });

  test('rejects the 10-digit number seen on training and other bad input', () {
    for (final n in [
      '0143534334', '01212345678', '01012345678', '1712345678',
      '017123456789', '', 'abc01712345678',
    ]) {
      expect(isValidBdMobile(n), isFalse, reason: n);
    }
  });

  test('normalizeBdMobile strips spaces and dashes only', () {
    expect(normalizeBdMobile(' 017-1234 5678 '), '01712345678');
    expect(normalizeBdMobile('+8801712345678'), '+8801712345678');
  });

  test('recognises the backend invalid-number rejection', () {
    expect(
        isInvalidMobileError(
            const ShukheeBookingException('Invalid Bangladeshi mobile number')),
        isTrue);
    expect(isInvalidMobileError(const ShukheeBookingException('Network error')),
        isFalse);
  });
}
