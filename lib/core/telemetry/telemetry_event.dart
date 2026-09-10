/// On-device telemetry event model for the AI Scribe / Counselling report.
///
/// ## Why this data is deliberately not patient-linked
///
/// [AppDatabase.wipeAllData] truncates every table it knows about, and it runs
/// on logout **and after every successful online login** — so anything stored
/// in a wiped table is destroyed on essentially every login. Telemetry has to
/// outlive that to support a report for a past date range, which means the
/// `telemetry_events` table is intentionally excluded from the wipe.
///
/// That exclusion is only defensible if the rows are not patient data. So this
/// model carries **no patient id, no member id and no encounter id** — the only
/// visit correlator is [visitUuid], a random id minted per visit for telemetry
/// alone and never used to look anything up. Every metric the report produces
/// is a per-visit or per-user aggregate, so none of them need a patient link.
///
/// Payloads must stay counts, durations, coarse categories and form **field
/// ids** — never a field *value*, transcript text, or free text an SK typed.
/// Field ids are form schema, not patient information.
library;

import 'dart:convert';

/// Discriminator for [TelemetryEvent.eventType].
abstract final class TelemetryEventType {
  TelemetryEventType._();

  /// One per completed visit. Carries the AI-Scribe-vs-manual split, the
  /// duration, and the per-field provenance buckets (report metrics 1-4).
  static const String visitCompleted = 'visit_completed';

  /// One per share tap on the counselling screen (report metric 5).
  static const String counsellingShare = 'counselling_share';
}

/// Lifecycle of a row's journey to the (not yet built) server.
abstract final class TelemetryUploadStatus {
  TelemetryUploadStatus._();

  static const String pending = 'pending';
  static const String uploaded = 'uploaded';
}

/// Where a share tap happened. Counselling surfaces answer "did the SK share
/// the counselling message"; the contact surfaces are direct patient contact
/// and would inflate that number if lumped in with it.
abstract final class TelemetryShareSurface {
  TelemetryShareSurface._();

  /// The standalone counselling screen (`/counselling`).
  static const String counselling = 'counselling';

  /// Step 3 of the visit flow — its own near-identical copy of the share row.
  static const String visitFlow = 'visitFlow';

  /// CCE alerts drawer: contacting a patient about a referral.
  static const String cceDrawer = 'cceDrawer';

  /// Patient contact sheet: calling/messaging a patient directly.
  static const String contactSheet = 'contactSheet';

  /// Surfaces that count toward the counselling-share metric.
  static const Set<String> counsellingSurfaces = {counselling, visitFlow};
}

/// Channel offered by the counselling screen's share row.
abstract final class TelemetryShareChannel {
  TelemetryShareChannel._();

  static const String sms = 'sms';
  static const String whatsapp = 'whatsapp';
}

/// A single persisted telemetry row.
class TelemetryEvent {
  const TelemetryEvent({
    required this.id,
    required this.eventType,
    required this.occurredAt,
    required this.appVersion,
    required this.appBuild,
    required this.payloadVersion,
    required this.payload,
    this.visitUuid,
    this.skUserId,
    this.capturedTenantId,
    this.uploadStatus = TelemetryUploadStatus.pending,
    this.uploadedAt,
  });

  /// Client-generated UUID. Doubles as the server's dedup/upsert key so a lost
  /// upload response cannot double-count the event on retry.
  final String id;

  /// One of [TelemetryEventType].
  final String eventType;

  /// Epoch ms, UTC. The report buckets this to a local calendar date at query
  /// time rather than storing a pre-bucketed day, so the date range can be
  /// re-interpreted in a different timezone without rewriting rows.
  final int occurredAt;

  /// Random per-visit correlator — **not** the encounter id. Null for events
  /// that aren't visit-scoped.
  final String? visitUuid;

  /// `provenance.spiceUserId`. Needed because metric 1 counts *users*, which a
  /// single device can never answer on its own.
  final String? skUserId;

  /// Tenant of the SK who was signed in when this event was *captured*.
  ///
  /// Needed because the queue outlives a session: a shared device wipes local
  /// data when a different SK signs in, but telemetry is deliberately kept
  /// (see AppDatabase._allTables), so a backlog can be uploaded during a
  /// later SK's session. The server stamps its own trusted tenant from that
  /// uploading session; without this field an event captured by tenant A and
  /// uploaded by tenant B would be credited to B. Reports attribute by this
  /// value and fall back to the session tenant when it is absent (rows
  /// captured before this field existed). Envelope field, not part of
  /// [payload] — so [kTelemetryPayloadVersion] is unchanged; a reader keys
  /// off the field being null, not off a version number.
  final int? capturedTenantId;

  /// Build identity, so a shift in a metric can be attributed to a release
  /// rather than mistaken for a change in behaviour.
  final String appVersion;
  final int appBuild;

  /// Schema version of [payload]. These rows persist for months while the
  /// payload shape evolves, so a reader must know which shape it is holding.
  final int payloadVersion;

  /// Event-specific JSON body. See [VisitCompletedPayload] /
  /// [CounsellingSharePayload].
  final Map<String, dynamic> payload;

  final String uploadStatus;
  final int? uploadedAt;

  DateTime get occurredAtDate =>
      DateTime.fromMillisecondsSinceEpoch(occurredAt);

  Map<String, Object?> toDb() => {
        'id': id,
        'event_type': eventType,
        'occurred_at': occurredAt,
        'visit_uuid': visitUuid,
        'sk_user_id': skUserId,
        'captured_tenant_id': capturedTenantId,
        'app_version': appVersion,
        'app_build': appBuild,
        'payload_version': payloadVersion,
        'payload': jsonEncode(payload),
        'upload_status': uploadStatus,
        'uploaded_at': uploadedAt,
      };

  static TelemetryEvent fromDb(Map<String, Object?> row) => TelemetryEvent(
        id: row['id'] as String,
        eventType: row['event_type'] as String,
        occurredAt: row['occurred_at'] as int,
        visitUuid: row['visit_uuid'] as String?,
        skUserId: row['sk_user_id'] as String?,
        capturedTenantId: row['captured_tenant_id'] as int?,
        appVersion: row['app_version'] as String? ?? '',
        appBuild: row['app_build'] as int? ?? 0,
        payloadVersion: row['payload_version'] as int? ?? 1,
        payload: _decodePayload(row['payload']),
        uploadStatus:
            row['upload_status'] as String? ?? TelemetryUploadStatus.pending,
        uploadedAt: row['uploaded_at'] as int?,
      );

  /// A row whose payload cannot be parsed is still a countable event, so this
  /// degrades to an empty map rather than throwing and losing the whole range.
  static Map<String, dynamic> _decodePayload(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }
}

/// Current [TelemetryEvent.payloadVersion] written by this build.
/// Bumped to 2 when the field buckets were split: `prefilled`, `derived` and
/// `aiOverridden` were added, and `manual` narrowed to mean "the SK typed it".
/// A v1 row has none of those keys — readers must default them to empty rather
/// than present a zero as a finding.
const int kTelemetryPayloadVersion = 3;

/// The AI feature these events belong to, matching the server's feature
/// registry key. A constant rather than a literal at the send site so adding a
/// second feature is a new constant, not a search for string duplicates.
const String kTelemetryAiFeatureScribe = 'scribe';

/// Body of a [TelemetryEventType.visitCompleted] event — report metrics 1-4.
class VisitCompletedPayload {
  const VisitCompletedPayload({
    required this.programmes,
    required this.scribeUsed,
    required this.aiFilled,
    required this.aiCorrected,
    required this.aiAcceptedUnchanged,
    required this.manual,
    required this.empty,
    this.prefilled = const [],
    this.derived = const [],
    this.aiOverridden = const [],
    this.scribeStartedAtMs,
    this.scribeEndedAtMs,
    this.manualEditingMs,
    this.outcome,
    this.failureReasons,
    required this.libraryTotal,
    required this.renderedTotal,
    required this.extractableVisible,
    this.durationMs,
  });

  /// Active form types for the visit (e.g. `['anc', 'ncd']`).
  final List<String> programmes;

  /// True when any field on the form carried a non-manual provenance.
  final bool scribeUsed;

  /// Wall-clock `now - encounters.started_at`. Null when the encounter row was
  /// not resolvable. **Includes time the app spent backgrounded**, so the
  /// report uses a median and trims outliers rather than a raw mean.
  final int? durationMs;

  /// Field ids by provenance bucket. Ids, never values — see the library doc.
  ///
  /// [aiFilled] is the union of [aiCorrected] and [aiAcceptedUnchanged].
  /// [aiAcceptedUnchanged] means the SK did not edit the AI's value — which is
  /// *not* the same as the SK having reviewed and approved it, because the
  /// live scribe path never sets an explicit accept. Correction rate derived
  /// from these is therefore a lower bound on error.
  final List<String> aiFilled;
  final List<String> aiCorrected;
  final List<String> aiAcceptedUnchanged;
  /// Fields the SK actually typed. Narrowed in payload v2: previously this
  /// also swept up anything with no recorded provenance, which meant
  /// history-preloaded and mirror-written values were reported as manual
  /// effort.
  final List<String> manual;

  /// Loaded from history / chronic record / a prior visit. Neither AI nor SK.
  final List<String> prefilled;

  /// Computed from other fields (BMI, EDD, follow-up dates). Neither AI nor SK.
  final List<String> derived;

  /// AI proposed a value but the SK had already filled the field, so the
  /// proposal was rejected. The only visible signal for "SK typed first, AI
  /// disagreed" — a case [aiCorrected] cannot see, because no AI value was
  /// ever placed to be edited.
  final List<String> aiOverridden;

  final List<String> empty;

  /// Wall-clock bounds of the scribe session(s), epoch ms, or null when AI
  /// Scribe never ran on this visit. Not derived from when fields landed:
  /// fills arrive after upload and processing, so a fill time would overstate
  /// when the SK stopped talking.
  final int? scribeStartedAtMs;
  final int? scribeEndedAtMs;

  /// Wall-clock from scribe end to submit. A proxy for editing effort, not
  /// keystroke timing — it includes any pause the SK took. Null when no
  /// scribe session ran.
  final int? manualEditingMs;

  /// `success` | `partial` | `failed`, or null when AI Scribe never ran.
  /// Three states because "ran and everything was rejected" and "filled the
  /// form cleanly" are both non-events under a success flag.
  final String? outcome;

  /// Why proposals were dropped, by category. Categories only — never a field
  /// id or a value.
  final Map<String, int>? failureReasons;

  /// Three candidate denominators for the capture rate, all emitted so the
  /// definition can change later without re-instrumenting:
  /// every field the programme declares; every field the layout rendered; and
  /// only those both extractable and visible when the extraction ran.
  final int libraryTotal;
  final int renderedTotal;
  final int extractableVisible;

  Map<String, dynamic> toJson() => {
        'programmes': programmes,
        'scribeUsed': scribeUsed,
        if (durationMs != null) 'durationMs': durationMs,
        'fields': {
          'aiFilled': aiFilled,
          'aiCorrected': aiCorrected,
          'aiAcceptedUnchanged': aiAcceptedUnchanged,
          'manual': manual,
          'prefilled': prefilled,
          'derived': derived,
          'aiOverridden': aiOverridden,
          'empty': empty,
        },
        'denominators': {
          'libraryTotal': libraryTotal,
          'renderedTotal': renderedTotal,
          'extractableVisible': extractableVisible,
        },
        // Omitted rather than sent as null: a reader distinguishes "not
        // measured" from "measured as zero" by the key's absence, and older
        // rows have no key either.
        if (scribeStartedAtMs != null) 'scribeStartedAt': scribeStartedAtMs,
        if (scribeEndedAtMs != null) 'scribeEndedAt': scribeEndedAtMs,
        if (manualEditingMs != null) 'manualEditingMs': manualEditingMs,
        if (outcome != null) 'outcome': outcome,
        if (failureReasons != null) 'failureReasons': failureReasons,
      };

  static VisitCompletedPayload fromJson(Map<String, dynamic> json) {
    final fields = (json['fields'] as Map?)?.cast<String, dynamic>() ?? const {};
    final denominators =
        (json['denominators'] as Map?)?.cast<String, dynamic>() ?? const {};
    return VisitCompletedPayload(
      programmes: _strings(json['programmes']),
      scribeUsed: json['scribeUsed'] == true,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      scribeStartedAtMs: (json['scribeStartedAt'] as num?)?.toInt(),
      scribeEndedAtMs: (json['scribeEndedAt'] as num?)?.toInt(),
      manualEditingMs: (json['manualEditingMs'] as num?)?.toInt(),
      outcome: json['outcome'] as String?,
      failureReasons: (json['failureReasons'] as Map?)
          ?.cast<String, dynamic>()
          .map((k, v) => MapEntry(k, (v as num).toInt())),
      aiFilled: _strings(fields['aiFilled']),
      aiCorrected: _strings(fields['aiCorrected']),
      aiAcceptedUnchanged: _strings(fields['aiAcceptedUnchanged']),
      manual: _strings(fields['manual']),
      // Absent on v1 rows — default to empty, never to a meaningful zero.
      prefilled: _strings(fields['prefilled']),
      derived: _strings(fields['derived']),
      aiOverridden: _strings(fields['aiOverridden']),
      empty: _strings(fields['empty']),
      libraryTotal: (denominators['libraryTotal'] as num?)?.toInt() ?? 0,
      renderedTotal: (denominators['renderedTotal'] as num?)?.toInt() ?? 0,
      extractableVisible:
          (denominators['extractableVisible'] as num?)?.toInt() ?? 0,
    );
  }

  static List<String> _strings(Object? raw) => raw is List
      ? raw.map((e) => e.toString()).toList()
      : const <String>[];
}

/// Body of a [TelemetryEventType.counsellingShare] event — report metric 5.
class CounsellingSharePayload {
  const CounsellingSharePayload({
    required this.channel,
    required this.hasMessage,
    required this.launched,
    this.surface = TelemetryShareSurface.counselling,
  });

  /// One of [TelemetryShareChannel].
  final String channel;

  /// One of [TelemetryShareSurface]. Defaults to `counselling` so a payload
  /// written before this field existed still reads as a counselling share.
  final String surface;

  /// Whether a counselling message existed to share at all — distinguishes a
  /// tap that could never have sent anything from a real share attempt.
  final bool hasMessage;

  /// True when the OS compose sheet was actually opened (`canLaunchUrl`
  /// passed and `launchUrl` was called). **This is intent, not delivery** —
  /// whether the SK then pressed send inside the messaging app is invisible
  /// to us, so the report must say "compose opened", never "sent".
  final bool launched;

  Map<String, dynamic> toJson() => {
        'channel': channel,
        'surface': surface,
        'hasMessage': hasMessage,
        'launched': launched,
      };

  static CounsellingSharePayload fromJson(Map<String, dynamic> json) =>
      CounsellingSharePayload(
        channel: json['channel']?.toString() ?? '',
        surface: json['surface']?.toString() ??
            TelemetryShareSurface.counselling,
        hasMessage: json['hasMessage'] == true,
        launched: json['launched'] == true,
      );
}
