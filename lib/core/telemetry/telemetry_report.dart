/// Turns raw [TelemetryEvent] rows into the five reported metric groups.
///
/// Pure Dart — no Flutter, no database, no clock. Everything it needs arrives
/// as arguments, so the whole report is unit-testable and the same logic can be
/// mirrored server-side later without porting a UI or a DAO.
///
/// ## Reading the rates honestly
///
/// Every rate here is `double?`, and null means "no denominator" — not zero.
/// A visit where AI Scribe was never started has no capture rate; rendering
/// that as `0%` would understate the tool. Callers must render null as an
/// em dash, never coerce it.
library;

import 'telemetry_event.dart';

/// Per-field-id tally: how often AI filled it, and how often the SK then
/// changed it. This is what answers "which fields is AI bad at".
class FieldAccuracy {
  const FieldAccuracy({
    required this.fieldId,
    required this.filled,
    required this.corrected,
  });

  final String fieldId;
  final int filled;
  final int corrected;

  /// Share of fills the SK had to change. Null when never filled.
  double? get correctionRatePct => filled == 0 ? null : corrected / filled * 100;
}

/// Aggregated result for one date range.
class TelemetryReport {
  const TelemetryReport({
    required this.from,
    required this.to,
    required this.visitCount,
    required this.scribeVisitCount,
    required this.manualVisitCount,
    required this.usersUsingScribe,
    required this.usersManualOnly,
    required this.scribeMedianDurationMs,
    required this.manualMedianDurationMs,
    required this.scribeDurationSampleCount,
    required this.manualDurationSampleCount,
    required this.totalAiFields,
    required this.totalExtractableVisible,
    required this.totalRendered,
    required this.totalLibrary,
    required this.aiFilledTotal,
    required this.aiCorrectedTotal,
    required this.aiAcceptedUnchangedTotal,
    required this.manualFieldTotal,
    required this.prefilledTotal,
    required this.derivedTotal,
    required this.aiOverriddenTotal,
    required this.fieldAccuracy,
    required this.smsComposeOpened,
    required this.whatsappComposeOpened,
    required this.contactSmsOpened,
    required this.contactWhatsappOpened,
  });

  final DateTime from;
  final DateTime to;

  // ── Metric 1: adoption ────────────────────────────────────────────────────
  final int visitCount;
  final int scribeVisitCount;
  final int manualVisitCount;

  /// Distinct SKs with at least one AI-Scribe visit in range.
  final int usersUsingScribe;

  /// Distinct SKs whose every visit in range was manual. Disjoint from
  /// [usersUsingScribe] — an SK who used scribe even once counts as adopting,
  /// so the two sum to the total distinct SKs seen.
  final int usersManualOnly;

  // ── Metric 2: time to complete ────────────────────────────────────────────
  /// **Median**, not mean. Duration is wall-clock `now - started_at`, so a
  /// visit left open while the app was backgrounded shows up as hours; a mean
  /// would be dragged around by those. The manual figure is the control — the
  /// scribe number alone says nothing.
  final int? scribeMedianDurationMs;
  final int? manualMedianDurationMs;
  final int scribeDurationSampleCount;
  final int manualDurationSampleCount;

  // ── Metric 3: fields captured ─────────────────────────────────────────────
  final int totalAiFields;

  /// The three candidate denominators, summed across visits. [captureRatePct]
  /// uses [totalExtractableVisible] as the honest one — a field the SK could
  /// not see was never a capture opportunity — but all three are exposed so
  /// the definition can be revisited without re-instrumenting.
  final int totalExtractableVisible;
  final int totalRendered;
  final int totalLibrary;

  // ── Metric 4: correction ──────────────────────────────────────────────────
  final int aiFilledTotal;
  final int aiCorrectedTotal;
  final int aiAcceptedUnchangedTotal;

  /// Fields the SK typed. Reported so a manual-effort claim can be checked
  /// against what actually happened — its absence from the UI is why a wrong
  /// figure went unnoticed until a hand ground-truth run.
  final int manualFieldTotal;

  /// Loaded from history, and computed from other fields. Neither AI nor SK,
  /// broken out so they can never be read as manual effort.
  final int prefilledTotal;
  final int derivedTotal;

  /// AI proposed a value the SK had already filled, so it was rejected.
  final int aiOverriddenTotal;

  /// Worst-first, so the fields AI struggles with are at the top.
  final List<FieldAccuracy> fieldAccuracy;

  // ── Metric 5: counselling share ───────────────────────────────────────────
  /// Compose sheets **opened**, not messages delivered — `launchUrl` hands off
  /// to the OS and we never learn whether the SK pressed send.
  /// Counselling surfaces only (the counselling screen and Step 3 of the
  /// visit flow) — this is the "Send SMS in the Counselling Guide" metric.
  final int smsComposeOpened;
  final int whatsappComposeOpened;

  /// Direct patient contact from the CCE drawer / contact sheet. Counted
  /// separately: lumping it in would inflate counselling shares with taps
  /// that have nothing to do with counselling.
  final int contactSmsOpened;
  final int contactWhatsappOpened;

  int get totalUsers => usersUsingScribe + usersManualOnly;

  /// Average AI-filled fields per AI-Scribe visit. Null when there were none —
  /// averaging over manual visits would dilute this into meaninglessness.
  double? get avgAiFieldsPerScribeVisit =>
      scribeVisitCount == 0 ? null : totalAiFields / scribeVisitCount;

  /// Share of the fields the SK could actually see that AI populated.
  double? get captureRatePct => totalExtractableVisible == 0
      ? null
      : totalAiFields / totalExtractableVisible * 100;

  /// Share of AI proposals the SK did not accept — corrections **plus** the
  /// cases where the SK had already filled the field and AI was overruled.
  ///
  /// A truer disagreement measure than [manualCorrectionRatePct]: that one can
  /// only see fields AI reached first, so it is blind to "SK typed it, AI
  /// proposed something else". Null when AI proposed nothing.
  double? get disagreementRatePct {
    final proposals = aiFilledTotal + aiOverriddenTotal;
    if (proposals == 0) return null;
    return (aiCorrectedTotal + aiOverriddenTotal) / proposals * 100;
  }

  /// Share of AI-filled fields the SK subsequently changed.
  ///
  /// A **lower bound on error**: the live scribe path has no explicit accept,
  /// so "not corrected" includes fields the SK never reviewed. Good for trend,
  /// not a claim about accuracy.
  double? get manualCorrectionRatePct =>
      aiFilledTotal == 0 ? null : aiCorrectedTotal / aiFilledTotal * 100;

  /// A zeroed report for a range with no rows — lets the UI render the same
  /// layout instead of branching on empty.
  static TelemetryReport emptyFor(DateTime from, DateTime to) => TelemetryReport(
        from: from,
        to: to,
        visitCount: 0,
        scribeVisitCount: 0,
        manualVisitCount: 0,
        usersUsingScribe: 0,
        usersManualOnly: 0,
        scribeMedianDurationMs: null,
        manualMedianDurationMs: null,
        scribeDurationSampleCount: 0,
        manualDurationSampleCount: 0,
        totalAiFields: 0,
        totalExtractableVisible: 0,
        totalRendered: 0,
        totalLibrary: 0,
        aiFilledTotal: 0,
        aiCorrectedTotal: 0,
        aiAcceptedUnchangedTotal: 0,
        manualFieldTotal: 0,
        prefilledTotal: 0,
        derivedTotal: 0,
        aiOverriddenTotal: 0,
        fieldAccuracy: const [],
        smsComposeOpened: 0,
        whatsappComposeOpened: 0,
        contactSmsOpened: 0,
        contactWhatsappOpened: 0,
      );
}

/// Builds a [TelemetryReport] from the rows in a date range.
abstract final class TelemetryReportBuilder {
  TelemetryReportBuilder._();

  static TelemetryReport build({
    required DateTime from,
    required DateTime to,
    required List<TelemetryEvent> events,
  }) {
    var visitCount = 0;
    var scribeVisitCount = 0;
    var manualVisitCount = 0;
    var totalAiFields = 0;
    var totalExtractableVisible = 0;
    var totalRendered = 0;
    var totalLibrary = 0;
    var aiFilledTotal = 0;
    var aiCorrectedTotal = 0;
    var aiAcceptedUnchangedTotal = 0;
    var manualFieldTotal = 0;
    var prefilledTotal = 0;
    var derivedTotal = 0;
    var aiOverriddenTotal = 0;
    var smsComposeOpened = 0;
    var whatsappComposeOpened = 0;
    var contactSmsOpened = 0;
    var contactWhatsappOpened = 0;

    final scribeUsers = <String>{};
    final allUsers = <String>{};
    final scribeDurations = <int>[];
    final manualDurations = <int>[];
    final filledByField = <String, int>{};
    final correctedByField = <String, int>{};

    for (final event in events) {
      switch (event.eventType) {
        case TelemetryEventType.visitCompleted:
          final p = VisitCompletedPayload.fromJson(event.payload);
          visitCount++;
          final user = event.skUserId;
          if (user != null && user.isNotEmpty) allUsers.add(user);

          if (p.scribeUsed) {
            scribeVisitCount++;
            if (user != null && user.isNotEmpty) scribeUsers.add(user);
            if (p.durationMs != null) scribeDurations.add(p.durationMs!);
          } else {
            manualVisitCount++;
            if (p.durationMs != null) manualDurations.add(p.durationMs!);
          }

          totalAiFields += p.aiFilled.length;
          totalExtractableVisible += p.extractableVisible;
          totalRendered += p.renderedTotal;
          totalLibrary += p.libraryTotal;
          aiFilledTotal += p.aiFilled.length;
          aiCorrectedTotal += p.aiCorrected.length;
          aiAcceptedUnchangedTotal += p.aiAcceptedUnchanged.length;
          manualFieldTotal += p.manual.length;
          prefilledTotal += p.prefilled.length;
          derivedTotal += p.derived.length;
          aiOverriddenTotal += p.aiOverridden.length;

          for (final id in p.aiFilled) {
            filledByField[id] = (filledByField[id] ?? 0) + 1;
          }
          for (final id in p.aiCorrected) {
            correctedByField[id] = (correctedByField[id] ?? 0) + 1;
          }

        case TelemetryEventType.counsellingShare:
          final p = CounsellingSharePayload.fromJson(event.payload);
          if (!p.launched) break; // a blocked tap never opened anything
          final isCounselling =
              TelemetryShareSurface.counsellingSurfaces.contains(p.surface);
          switch (p.channel) {
            case TelemetryShareChannel.sms:
              if (isCounselling) {
                smsComposeOpened++;
              } else {
                contactSmsOpened++;
              }
            case TelemetryShareChannel.whatsapp:
              if (isCounselling) {
                whatsappComposeOpened++;
              } else {
                contactWhatsappOpened++;
              }
          }
      }
    }

    final accuracy = filledByField.entries
        .map((e) => FieldAccuracy(
              fieldId: e.key,
              filled: e.value,
              corrected: correctedByField[e.key] ?? 0,
            ))
        .toList()
      // Worst first: highest correction rate, then most-corrected as the
      // tie-break so a 1-of-1 field doesn't outrank a 20-of-40 one.
      ..sort((a, b) {
        final byRate = (b.correctionRatePct ?? 0).compareTo(a.correctionRatePct ?? 0);
        return byRate != 0 ? byRate : b.corrected.compareTo(a.corrected);
      });

    return TelemetryReport(
      from: from,
      to: to,
      visitCount: visitCount,
      scribeVisitCount: scribeVisitCount,
      manualVisitCount: manualVisitCount,
      usersUsingScribe: scribeUsers.length,
      usersManualOnly: allUsers.difference(scribeUsers).length,
      scribeMedianDurationMs: _median(scribeDurations),
      manualMedianDurationMs: _median(manualDurations),
      scribeDurationSampleCount: scribeDurations.length,
      manualDurationSampleCount: manualDurations.length,
      totalAiFields: totalAiFields,
      totalExtractableVisible: totalExtractableVisible,
      totalRendered: totalRendered,
      totalLibrary: totalLibrary,
      aiFilledTotal: aiFilledTotal,
      aiCorrectedTotal: aiCorrectedTotal,
      aiAcceptedUnchangedTotal: aiAcceptedUnchangedTotal,
      manualFieldTotal: manualFieldTotal,
      prefilledTotal: prefilledTotal,
      derivedTotal: derivedTotal,
      aiOverriddenTotal: aiOverriddenTotal,
      fieldAccuracy: accuracy,
      smsComposeOpened: smsComposeOpened,
      whatsappComposeOpened: whatsappComposeOpened,
      contactSmsOpened: contactSmsOpened,
      contactWhatsappOpened: contactWhatsappOpened,
    );
  }

  /// Median of [values], or null when empty. Even-length lists average the two
  /// middle samples.
  static int? _median(List<int> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }
}
