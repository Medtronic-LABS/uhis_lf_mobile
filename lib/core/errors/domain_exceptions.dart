/// Typed exception hierarchy for uhis_lf_mobile.
///
/// All repository and service classes must throw only named subclasses of
/// [DomainException] — never the raw [Exception] class or a string literal.
/// The Notifier/ViewModel layer catches these, maps them to localized messages
/// via [AppStrings], and exposes the result through [AsyncValue].
library;

/// Base class for all application-level exceptions.
abstract class DomainException implements Exception {
  final String? localizedMessage;
  const DomainException([this.localizedMessage]);

  @override
  String toString() =>
      localizedMessage != null ? '$runtimeType: $localizedMessage' : runtimeType.toString();
}

// ── Auth ─────────────────────────────────────────────────────────────────────

/// 401 — credentials rejected or token expired.
class UnauthorizedException extends DomainException {
  const UnauthorizedException([super.localizedMessage]);
}

/// 403 — authenticated but not permitted for this resource.
class ForbiddenException extends DomainException {
  const ForbiddenException([super.localizedMessage]);
}

/// Offline session exceeded the max allowed duration; re-login required.
class SessionExpiredException extends DomainException {
  const SessionExpiredException([super.localizedMessage]);
}

// ── Network ───────────────────────────────────────────────────────────────────

/// HTTP or socket-level failure; includes timeout and connection refused.
class NetworkException extends DomainException {
  final Object? cause;
  const NetworkException({this.cause, String? message}) : super(message);
}

/// Server returned an unexpected response format (contract violation).
class ContractException extends DomainException {
  final int? statusCode;
  const ContractException({this.statusCode, String? message}) : super(message);
}

// ── Sync ──────────────────────────────────────────────────────────────────────

/// Push op returned status:conflict — supervisor resolution required.
class SyncConflictException extends DomainException {
  const SyncConflictException([super.localizedMessage]);
}

/// Push op returned status:rejected — op permanently dequeued.
class SyncRejectedException extends DomainException {
  const SyncRejectedException([super.localizedMessage]);
}

// ── Error message mapper ──────────────────────────────────────────────────────

/// Converts any caught [exception] into a short, human-readable message safe
/// to show a non-technical user. Strips Dio stack frames, host names, errno
/// codes, and Java-style exception prefixes.
///
/// Import `package:dio/dio.dart` in the calling file — this helper is typed
/// against [Object] so callers without Dio on their import list still compile.
class NetworkErrorMapper {
  NetworkErrorMapper._();

  /// Returns a plain-English error string for [e].
  static String friendly(Object e) {
    // Import guard: use string matching so we don't add a hard Dio dep here.
    final typeName = e.runtimeType.toString();
    if (typeName == 'DioException' || typeName.startsWith('DioException')) {
      return _fromDio(e);
    }
    return _generic();
  }

  /// Called when the exception is known to be a DioException.
  /// Uses duck-typing via dynamic so this file stays Dio-import-free.
  static String _fromDio(Object e) {
    try {
      // ignore: avoid_dynamic_calls
      final dynamic d = e;
      final typeIndex = d.type.index as int;
      final statusCode = d.response?.statusCode as int?;

      // DioExceptionType indices (stable across Dio 5.x):
      // 0=connectionTimeout, 1=sendTimeout, 2=receiveTimeout,
      // 3=badCertificate, 4=badResponse, 5=cancel, 6=connectionError, 7=unknown
      switch (typeIndex) {
        case 0:
        case 1:
        case 2:
          return 'Connection timed out. Check your signal and try again.';
        case 5:
          return 'Request was cancelled. Please try again.';
        case 6:
          return 'No internet connection. Check your signal and try again.';
        case 4:
          return _fromStatusCode(statusCode);
        default:
          return _generic();
      }
    } catch (_) {
      return _generic();
    }
  }

  static String _fromStatusCode(int? code) {
    if (code == null) return _generic();
    if (code == 401 || code == 403) {
      return 'Access denied. Please log out and log back in.';
    }
    if (code == 404) return 'The requested data was not found.';
    if (code == 408 || code == 429) return 'Server is busy. Please try again in a moment.';
    if (code >= 500) return 'Server error. Please try again in a moment.';
    return _generic();
  }

  static String _generic() => 'Something went wrong. Please try again.';
}

// ── AI services ───────────────────────────────────────────────────────────────

/// Scribe audio upload failed (network or server error).
class ScribeUploadException extends DomainException {
  const ScribeUploadException([super.localizedMessage]);
}

/// CDS/pathway service unavailable and local rule engine also failed.
class CdssUnavailableException extends DomainException {
  const CdssUnavailableException([super.localizedMessage]);
}

// ── Local DB ─────────────────────────────────────────────────────────────────

/// Drift/SQLite write or read failure.
class DatabaseException extends DomainException {
  final Object? cause;
  const DatabaseException({this.cause, String? message}) : super(message);
}
