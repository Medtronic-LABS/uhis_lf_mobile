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
