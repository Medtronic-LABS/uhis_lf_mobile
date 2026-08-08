import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/errors/domain_exceptions.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';

void main() {
  // AppLocale.current is a global static flag (the app's context-free
  // localization seam — see app_locale.dart) shared across the whole test
  // process. AppLocale.current defaults to bangla, so set english explicitly
  // and restore it afterwards or it leaks into unrelated test files run in
  // the same suite.
  setUp(() {
    AppLocale.current = AppLanguage.english;
  });

  tearDown(() {
    AppLocale.current = AppLanguage.english;
  });

  DioException dioOf(DioExceptionType type, {int? statusCode, bool withResponse = false}) {
    final requestOptions = RequestOptions(path: '/x');
    return DioException(
      requestOptions: requestOptions,
      type: type,
      response: (withResponse || statusCode != null)
          ? Response(requestOptions: requestOptions, statusCode: statusCode)
          : null,
    );
  }

  group('NetworkErrorMapper.friendly — DioException timeout types', () {
    test('connectionTimeout', () {
      expect(
        NetworkErrorMapper.friendly(dioOf(DioExceptionType.connectionTimeout)),
        'Connection timed out. Check your signal and try again.',
      );
    });

    test('sendTimeout', () {
      expect(
        NetworkErrorMapper.friendly(dioOf(DioExceptionType.sendTimeout)),
        'Connection timed out. Check your signal and try again.',
      );
    });

    test('receiveTimeout', () {
      expect(
        NetworkErrorMapper.friendly(dioOf(DioExceptionType.receiveTimeout)),
        'Connection timed out. Check your signal and try again.',
      );
    });
  });

  group('NetworkErrorMapper.friendly — DioException cancel/connectionError', () {
    test('cancel', () {
      expect(
        NetworkErrorMapper.friendly(dioOf(DioExceptionType.cancel)),
        'Request was cancelled. Please try again.',
      );
    });

    test('connectionError', () {
      expect(
        NetworkErrorMapper.friendly(dioOf(DioExceptionType.connectionError)),
        'No internet connection. Check your signal and try again.',
      );
    });
  });

  group('NetworkErrorMapper.friendly — DioException badResponse by status code', () {
    test('401 -> access denied', () {
      expect(
        NetworkErrorMapper.friendly(
          dioOf(DioExceptionType.badResponse, statusCode: 401),
        ),
        'Access denied. Please log out and log back in.',
      );
    });

    test('403 -> access denied', () {
      expect(
        NetworkErrorMapper.friendly(
          dioOf(DioExceptionType.badResponse, statusCode: 403),
        ),
        'Access denied. Please log out and log back in.',
      );
    });

    test('404 -> not found', () {
      expect(
        NetworkErrorMapper.friendly(
          dioOf(DioExceptionType.badResponse, statusCode: 404),
        ),
        'The requested data was not found.',
      );
    });

    test('408 -> server busy', () {
      expect(
        NetworkErrorMapper.friendly(
          dioOf(DioExceptionType.badResponse, statusCode: 408),
        ),
        'Server is busy. Please try again in a moment.',
      );
    });

    test('429 -> server busy', () {
      expect(
        NetworkErrorMapper.friendly(
          dioOf(DioExceptionType.badResponse, statusCode: 429),
        ),
        'Server is busy. Please try again in a moment.',
      );
    });

    test('500 -> server error', () {
      expect(
        NetworkErrorMapper.friendly(
          dioOf(DioExceptionType.badResponse, statusCode: 500),
        ),
        'Server error. Please try again in a moment.',
      );
    });

    test('null status code -> generic', () {
      expect(
        NetworkErrorMapper.friendly(
          dioOf(DioExceptionType.badResponse, withResponse: true),
        ),
        'Something went wrong. Please try again.',
      );
    });

    test('unmapped status code (418) -> generic', () {
      expect(
        NetworkErrorMapper.friendly(
          dioOf(DioExceptionType.badResponse, statusCode: 418),
        ),
        'Something went wrong. Please try again.',
      );
    });
  });

  group('NetworkErrorMapper.friendly — DioException default fallthrough', () {
    test('badCertificate -> generic', () {
      expect(
        NetworkErrorMapper.friendly(dioOf(DioExceptionType.badCertificate)),
        'Something went wrong. Please try again.',
      );
    });

    test('unknown -> generic', () {
      expect(
        NetworkErrorMapper.friendly(dioOf(DioExceptionType.unknown)),
        'Something went wrong. Please try again.',
      );
    });
  });

  group('NetworkErrorMapper.friendly — AuthException', () {
    test('non-empty message is returned verbatim', () {
      expect(
        NetworkErrorMapper.friendly(AuthException('Some backend message')),
        'Some backend message',
      );
    });

    test('empty message falls through to generic', () {
      expect(
        NetworkErrorMapper.friendly(AuthException('')),
        'Something went wrong. Please try again.',
      );
    });
  });

  group('NetworkErrorMapper.friendly — unrecognized exception types', () {
    test('plain Exception -> generic', () {
      expect(
        NetworkErrorMapper.friendly(Exception('boom')),
        'Something went wrong. Please try again.',
      );
    });

    test('StateError -> generic', () {
      expect(
        NetworkErrorMapper.friendly(StateError('x')),
        'Something went wrong. Please try again.',
      );
    });
  });
}
