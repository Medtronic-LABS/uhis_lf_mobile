import 'dart:math';

import 'naba_models.dart';

/// One picture chosen for the Step 3 guideline strip.
class SelectedGuidelineVisual {
  const SelectedGuidelineVisual({
    required this.pointerId,
    required this.caption,
    required this.image,
  });

  /// Guideline pointer id, e.g. `ANC-4.1`.
  final String pointerId;

  /// Caption in the app's language (never empty).
  final String caption;

  /// The pointer's first image (lowest `order`).
  final NabaVisualImage image;
}

/// Picks which guideline pictures Step 3 shows.
///
/// Every id the response cites is a candidate; a candidate is kept only when
/// `visuals` has at least one image for it and a caption in the app's
/// language. Up to [maxVisuals] are chosen at random, one picture per
/// guideline, seeded per visit so the same visit always shows the same set.
abstract final class GuidelineVisualSelector {
  static const int maxVisuals = 3;

  static List<SelectedGuidelineVisual> select(
    NabaResponse naba, {
    required bool bangla,
    required String seed,
    int max = maxVisuals,
  }) {
    final eligible = <SelectedGuidelineVisual>[];
    for (final id in citedIds(naba)) {
      final visual = naba.visuals[id];
      if (visual == null || visual.images.isEmpty) continue;
      final caption = visual.captionFor(bangla: bangla);
      if (caption.isEmpty) continue;
      eligible.add(
        SelectedGuidelineVisual(
          pointerId: id,
          caption: caption,
          image: visual.images.first,
        ),
      );
    }
    eligible.shuffle(Random(stableHash(seed)));
    return List.unmodifiable(eligible.take(max));
  }

  /// Every guideline id the response cites, first occurrence order, no
  /// duplicates.
  static List<String> citedIds(NabaResponse naba) {
    final ids = <String>{};
    for (final rows in naba.citations.values) {
      for (final row in rows) {
        ids.addAll(row);
      }
    }
    for (final finding in naba.clinicalFindings) {
      final id = finding.guidelineId;
      if (id != null) ids.add(id);
    }
    final referralId = naba.referralRecommendation?.guidelineId;
    if (referralId != null) ids.add(referralId);
    ids.addAll(naba.rationale.guidelineIds);
    ids.removeWhere((id) => id.trim().isEmpty);
    return List.unmodifiable(ids);
  }

  /// FNV-1a over the string's code units. Unlike [String.hashCode] this is
  /// the same on every run, so a reopened visit shows the same pictures.
  static int stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}
