import 'eye_care_status.dart';
import 'ncd_status.dart';

/// Cataract `encounter.customStatus` tokens, ported from Android SPICE
/// `AssessmentStatusGenerator.buildCataractStatuses`.
///
/// Spice order: eye-problem enums, then (when NCD service provided)
/// `UNCONTROLLED_BP` / `UNCONTROLLED_BG` from referral reasons, then
/// `GLASSES_SOLD`, then `NCD_SERVICE_IN_CATARACT_CAMP`, then
/// `REFERRED_FOR_OPERATION`, then the `GLASS_POWER:<power>` extra token.
abstract final class CataractStatus {
  CataractStatus._();

  static const String referredForOperation = 'REFERRED_FOR_OPERATION';
  static const String ncdServiceInCataractCamp = 'NCD_SERVICE_IN_CATARACT_CAMP';

  /// Builds customStatus from the inner `cataract` card body (post-transform,
  /// with `eyeTestOutcomes` — also accepts pre-transform `eyeDisease`).
  ///
  /// [referredReasons] are Spice wire reasons (`High BP` / `High BG`) used
  /// only when `ncdServiceProvided` is yes.
  static List<String> status(
    Map<String, dynamic>? cataractCard, {
    List<String> referredReasons = const [],
  }) {
    if (cataractCard == null || cataractCard.isEmpty) return const [];

    final ncdYes = cataractCard['ncdServiceProvided']
            ?.toString()
            .toLowerCase() ==
        'yes';

    // Reuse eye-care problem + glasses + power extraction, then insert the
    // cataract-only tokens before the glass-power extra (Spice appends
    // GLASS_POWER:* via extraTokens after all enums).
    final base = EyeCareStatus.status(cataractCard);
    final out = <String>[];
    String? glassPowerToken;
    for (final token in base) {
      if (token.startsWith(EyeCareStatus.glassPowerPrefix)) {
        glassPowerToken = token;
      } else if (token == EyeCareStatus.glassesSold) {
        // Hold GLASSES_SOLD until after uncontrolled tokens (Spice order).
        continue;
      } else {
        out.add(token);
      }
    }

    if (ncdYes) {
      if (referredReasons.contains(NcdStatus.reasonHighBp)) {
        out.add(NcdStatus.uncontrolledBp);
      }
      if (referredReasons.contains(NcdStatus.reasonHighBg)) {
        out.add(NcdStatus.uncontrolledBg);
      }
    }

    if (cataractCard['haveTheGlassesBeenSold']?.toString().toLowerCase() ==
        'yes') {
      out.add(EyeCareStatus.glassesSold);
    }
    if (ncdYes) {
      out.add(ncdServiceInCataractCamp);
    }
    if (cataractCard['patientReferredForOperation']
            ?.toString()
            .toLowerCase() ==
        'yes') {
      out.add(referredForOperation);
    }
    if (glassPowerToken != null) out.add(glassPowerToken);
    return out;
  }
}
