import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/errors/domain_exceptions.dart';

void main() {
  group('DomainException hierarchy', () {
    group('UnauthorizedException', () {
      test('can be constructed without message', () {
        const e = UnauthorizedException();
        expect(e.localizedMessage, isNull);
        expect(e.toString(), equals('UnauthorizedException'));
        expect(e, isA<DomainException>());
        expect(e, isA<Exception>());
      });

      test('carries optional localized message', () {
        const e = UnauthorizedException('Session has expired');
        expect(e.localizedMessage, equals('Session has expired'));
        expect(e.toString(), contains('Session has expired'));
      });
    });

    group('ForbiddenException', () {
      test('can be constructed without message', () {
        const e = ForbiddenException();
        expect(e, isA<DomainException>());
      });
    });

    group('SessionExpiredException', () {
      test('can be constructed without message', () {
        const e = SessionExpiredException();
        expect(e, isA<DomainException>());
      });
    });

    group('NetworkException', () {
      test('can carry a cause object', () {
        final cause = Exception('timeout');
        final e = NetworkException(cause: cause, message: 'Connection failed');
        expect(e.cause, same(cause));
        expect(e.localizedMessage, equals('Connection failed'));
        expect(e, isA<DomainException>());
      });

      test('can be constructed without cause or message', () {
        const e = NetworkException();
        expect(e.cause, isNull);
        expect(e.localizedMessage, isNull);
      });
    });

    group('ContractException', () {
      test('carries status code', () {
        const e = ContractException(statusCode: 502, message: 'Bad Gateway');
        expect(e.statusCode, equals(502));
        expect(e.localizedMessage, equals('Bad Gateway'));
      });
    });

    group('SyncConflictException', () {
      test('can be constructed without message', () {
        const e = SyncConflictException();
        expect(e, isA<DomainException>());
      });
    });

    group('SyncRejectedException', () {
      test('can be constructed without message', () {
        const e = SyncRejectedException();
        expect(e, isA<DomainException>());
      });
    });

    group('ScribeUploadException', () {
      test('can be constructed without message', () {
        const e = ScribeUploadException();
        expect(e, isA<DomainException>());
      });
    });

    group('CdssUnavailableException', () {
      test('can be constructed without message', () {
        const e = CdssUnavailableException();
        expect(e, isA<DomainException>());
      });
    });

    group('DatabaseException', () {
      test('can carry a cause object', () {
        final cause = Exception('db locked');
        final e = DatabaseException(cause: cause, message: 'Write failed');
        expect(e.cause, same(cause));
        expect(e.localizedMessage, equals('Write failed'));
        expect(e, isA<DomainException>());
      });

      test('can be constructed without cause', () {
        const e = DatabaseException();
        expect(e.cause, isNull);
      });
    });

    group('DomainException.toString()', () {
      test('returns runtimeType when no message', () {
        expect(const UnauthorizedException().toString(), equals('UnauthorizedException'));
        expect(const DatabaseException().toString(), equals('DatabaseException'));
      });

      test('includes message when provided', () {
        expect(
          const UnauthorizedException('must re-login').toString(),
          equals('UnauthorizedException: must re-login'),
        );
      });
    });

    test('all subclasses are catchable as DomainException', () {
      final exceptions = <DomainException>[
        const UnauthorizedException(),
        const ForbiddenException(),
        const SessionExpiredException(),
        const NetworkException(),
        const ContractException(),
        const SyncConflictException(),
        const SyncRejectedException(),
        const ScribeUploadException(),
        const CdssUnavailableException(),
        const DatabaseException(),
      ];
      for (final e in exceptions) {
        expect(e, isA<DomainException>());
        expect(e, isA<Exception>());
      }
    });
  });
}
