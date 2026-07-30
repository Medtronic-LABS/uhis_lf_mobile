/// Regression test for the login flow surfacing a generic "Something went
/// wrong" message instead of the real reason a login attempt failed (e.g. the
/// server's "Account locked due to multiple invalid login attempts.").
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/errors/domain_exceptions.dart';

void main() {
  group('NetworkErrorMapper.friendly with AuthException', () {
    test('surfaces the AuthException message instead of the generic fallback',
        () {
      final e =
          AuthException('Account locked due to multiple invalid login attempts.');
      expect(
        NetworkErrorMapper.friendly(e),
        equals('Account locked due to multiple invalid login attempts.'),
      );
    });

    test('falls back to the generic message when AuthException has no message',
        () {
      final e = AuthException('');
      expect(NetworkErrorMapper.friendly(e),
          equals('Something went wrong. Please try again.'));
    });
  });

  group('extractLoginErrorMessage', () {
    test('reads the message field from a Map response body', () {
      expect(
        extractLoginErrorMessage(
            {'message': 'Account locked due to multiple invalid login attempts.'}),
        equals('Account locked due to multiple invalid login attempts.'),
      );
    });

    test('reads the message field from a JSON-string response body (web Dio)',
        () {
      expect(
        extractLoginErrorMessage('{"message":"Account locked."}'),
        equals('Account locked.'),
      );
    });

    test('returns null when the body has no message field', () {
      expect(extractLoginErrorMessage({'foo': 'bar'}), isNull);
    });

    test('returns null for malformed or absent bodies', () {
      expect(extractLoginErrorMessage('not json'), isNull);
      expect(extractLoginErrorMessage(null), isNull);
    });
  });
}
