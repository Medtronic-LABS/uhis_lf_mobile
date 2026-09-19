/// The single place every SMS / WhatsApp launcher records a share tap.
///
/// There are four such launchers in this app — the counselling screen, Step 3
/// of the visit flow, the CCE alerts drawer and the patient contact sheet —
/// with near-identical `whatsapp://send` → `wa.me` → `sms:` code. The first
/// pass at this feature instrumented only one of them, so a real SK tapping
/// "Send SMS" at the end of a visit recorded nothing. One helper means a fifth
/// launcher is covered by a single call rather than a copied block.
///
/// ## Resolve first, record after
///
/// Every call site records *after* `await launchUrl(...)`. Reading a provider
/// off `BuildContext` at that point is both a lint violation and unreliable:
/// if the share sheet caused the widget to be disposed, the read throws and
/// the tap is silently lost. So [shareTelemetryOf] is called before the await
/// and its result passed to [recordShareTap].
library;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'telemetry_service.dart';

/// Resolves the telemetry service. **Call before any `await`.**
///
/// Returns null when the provider isn't in the tree (widget tests), which
/// makes [recordShareTap] a no-op rather than a crash in a share action.
TelemetryService? shareTelemetryOf(BuildContext context) {
  try {
    return context.read<TelemetryService>();
  } on Object {
    return null;
  }
}

/// Records one share tap for the weekly report.
///
/// [launched] must be false when the OS compose sheet did not open, so the
/// report can separate real share attempts from taps that sent nothing. Even
/// then the tap is recorded: a channel an SK keeps tapping with no handler
/// installed is itself a finding.
void recordShareTap(
  TelemetryService? telemetry, {
  required String channel,
  required String surface,
  required bool hasMessage,
  required bool launched,
}) {
  telemetry?.recordCounsellingShare(
    channel: channel,
    surface: surface,
    hasMessage: hasMessage,
    launched: launched,
  );
}
