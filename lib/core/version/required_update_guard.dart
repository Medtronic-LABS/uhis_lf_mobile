/// Decides how hard the app may block on a backend-required update.
///
/// Rule (agreed after design review): block only where Google Play can
/// actually deliver the required build. Where it cannot — staged rollout not
/// reached this device yet, Play unusable, non-Play install — the user gets a
/// dismissible warning instead of a lockout, and hard blocking resumes on its
/// own the moment Play can deliver. The grace deadline is server-provided and
/// is carried in the policy as [AppVersionUpdateRequired.graceExpired]; this
/// file never reads a device clock.
library;

import 'app_version_service.dart';
import 'play_update_client.dart';

enum RequiredUpdateDecision {
  /// Play can deliver the required build: non-dismissible gate + update.
  blockWithUpdate,

  /// Play cannot deliver it yet, grace still running: dismissible warning.
  warn,

  /// Play cannot deliver it and grace has expired: dismissible warning with
  /// the support message; reported as stranded so support can follow up.
  warnStranded,
}

/// Pure decision from Play's snapshot (null when Play could not answer).
RequiredUpdateDecision decideRequiredUpdate({
  required PlayUpdateSnapshot? play,
  required int minVersionCode,
  required bool graceExpired,
}) {
  if (_canDeliver(play, minVersionCode)) {
    return RequiredUpdateDecision.blockWithUpdate;
  }
  return graceExpired
      ? RequiredUpdateDecision.warnStranded
      : RequiredUpdateDecision.warn;
}

bool _canDeliver(PlayUpdateSnapshot? play, int minVersionCode) {
  if (play == null) return false;
  // An interrupted immediate update or a finished flexible download is
  // already on the device — finishing it satisfies the requirement.
  if (play.immediateInProgress || play.flexibleDownloaded) return true;
  if (!play.updateOffered || !play.immediateAllowed) return false;
  final offered = play.availableVersionCode;
  // Null = Play did not say which build; an offered update is the best signal.
  return offered == null || offered >= minVersionCode;
}

/// Lets the login path ask the same question without depending on the
/// controller or on Flutter.
abstract interface class RequiredUpdateResolver {
  Future<RequiredUpdateDecision> resolve(AppVersionUpdateRequired required);
}

/// Pre-guard behaviour, kept as the default for callers (and tests) that do
/// not wire Play: a required update always blocks.
class AlwaysBlockRequiredUpdate implements RequiredUpdateResolver {
  const AlwaysBlockRequiredUpdate();

  @override
  Future<RequiredUpdateDecision> resolve(AppVersionUpdateRequired required) async =>
      RequiredUpdateDecision.blockWithUpdate;
}
