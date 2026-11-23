import 'package:flutter_test/flutter_test.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';
import 'package:uhis_next/core/analytics/analytics_events.dart';
import 'package:uhis_next/core/analytics/teleconsult_analytics.dart';

void main() {
  group('isValidBdMobile', () {
    test('accepts 11-digit BD mobiles, with or without 88 / +88', () {
      for (final n in ['01712345678', '01312345678', '8801912345678', '+8801512345678', '017-1234-5678', '017 1234 5678']) {
        expect(isValidBdMobile(n), isTrue, reason: n);
      }
    });

    test('rejects the 10-digit number seen on training and other bad input', () {
      for (final n in ['0143534334', '01212345678', '1712345678', '017123456789', '', 'abc01712345678']) {
        expect(isValidBdMobile(n), isFalse, reason: n);
      }
    });
  });

  test('sameBdMobile ignores formatting and the 88 prefix', () {
    expect(sameBdMobile('+8801712345678', '01712345678'), isTrue);
    expect(sameBdMobile('017-1234-5678', '01712345678'), isTrue);
    expect(sameBdMobile('01712345678', '01812345678'), isFalse);
    expect(sameBdMobile(null, '01712345678'), isFalse);
  });

  group('teleconsultFailureReason (backend messages from training)', () {
    test('invalid mobile number', () {
      expect(
        teleconsultFailureReason(const ShukheeBookingException('Invalid Bangladeshi mobile number')),
        AnalyticsValue.invalidMobile,
      );
    });

    test('inactive Shukhee account', () {
      expect(
        teleconsultFailureReason(
            const ShukheeNotProvisionedException("This Provider's Shukhee account is inactive.")),
        AnalyticsValue.accountInactive,
      );
      expect(
        teleconsultFailureReason(
            const ShukheeBookingException("This Provider's Shukhee account is inactive.")),
        AnalyticsValue.accountInactive,
      );
      expect(teleconsultFailureReason(const ShukheeNotProvisionedException('No provider')),
          AnalyticsValue.notProvisioned);
    });

    test('vendor and booking failures', () {
      expect(
        teleconsultFailureReason(const ShukheeBookingException('Could not reach Shukhee. Check your connection and try again.')),
        AnalyticsValue.vendorUnreachable,
      );
      expect(
        teleconsultFailureReason(const ShukheeBookingException('Could not resolve a Shukhee patient id for contact number x.')),
        AnalyticsValue.patientNotResolved,
      );
      expect(
        teleconsultFailureReason(const ShukheeBookingException('Booking the Shukhee instant call failed.')),
        AnalyticsValue.bookingFailed,
      );
      expect(teleconsultFailureReason(const ShukheeUnauthorizedException('no token')),
          AnalyticsValue.unauthorized);
      expect(teleconsultFailureReason(const ShukheeBookingException('something odd')), AnalyticsValue.other);
    });
  });

  test('teleconsultEndStatus: final status or timeout', () {
    expect(teleconsultEndStatus(const ShukheeStatus(status: 'completed')), 'completed');
    expect(teleconsultEndStatus(const ShukheeStatus(status: 'rejected')), 'rejected');
    expect(teleconsultEndStatus(const ShukheeStatus(status: 'pending')), AnalyticsValue.timeout);
    expect(teleconsultEndStatus(null), AnalyticsValue.timeout);
  });
}
