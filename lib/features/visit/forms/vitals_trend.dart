/// Pure-Dart rule-based trend detection across a patient's ANC visits.
///
/// No Flutter dependencies and no user-facing strings — this is the business
/// logic behind the "AI sees a trend across her N visits" card. Rules (no ML):
///
/// - Window = last **2** prior ANC visits + **today** (3 columns max).
/// - Systolic / diastolic / weight: show only with **3** readings and a rise
///   of **≥ 5** on **each** consecutive step (weight uses the same 5 kg rule).
/// - Urine protein (form field Urinary Albumin): show only with **3** captured
///   grades and **≥ 1 Present** (Trace / Absent alone do not open the row).
/// - Card shows only when at least one metric row qualifies.
///
/// All display formatting (column titles, urine-grade labels, footer copy)
/// lives in the widget layer via `UnifiedFormStrings`; this file only compares
/// numbers and returns booleans + raw values.
library;

/// Minimum step size (mmHg or kg) required between consecutive numeric readings.
const double kVitalsTrendMinStep = 5;

/// One visit's snapshot of the four tracked ANC vitals.
///
/// Any field may be `null` when that measurement was not captured that visit.
/// [date] is used only to derive a "N wk ago" column sub-label; it is optional.
class VisitVitals {
  const VisitVitals({
    this.date,
    this.systolic,
    this.diastolic,
    this.weight,
    this.urineProtein,
  });

  final DateTime? date;
  final int? systolic;
  final int? diastolic;
  final double? weight;

  /// Raw urine-protein grade as captured (e.g. `Absent` / `Trace` / `Present`);
  /// normalised for comparison by the analyzer.  `null` when not captured.
  /// Maps from form field Urinary Albumin.
  final String? urineProtein;

  bool get isEmpty =>
      systolic == null &&
      diastolic == null &&
      weight == null &&
      urineProtein == null;
}

/// Which of the four metrics a [VitalMetricTrend] describes.
enum VitalMetric { systolic, diastolic, weight, urineProtein }

/// The trend for a single metric across the visit sequence.
class VitalMetricTrend {
  const VitalMetricTrend({
    required this.metric,
    required this.values,
    required this.rising,
  });

  final VitalMetric metric;

  /// Comparable values per column, oldest-first, ending with "today".
  /// For [VitalMetric.urineProtein] these are ordinal ranks (0/1/2); a `null`
  /// means the reading was not captured that visit.  The widget formats them.
  final List<num?> values;

  /// True when this metric qualified as a trend signal for the card.
  final bool rising;
}

/// Column header data describing one visit in the trend table.
class VitalsTrendColumn {
  const VitalsTrendColumn({required this.isToday, this.visitNumber, this.daysAgo});

  final bool isToday;

  /// 1-based visit index for prior visits (`null` for the "today" column).
  final int? visitNumber;

  /// Days between this visit and today (`null` when the date is unknown).
  final int? daysAgo;
}

/// The full analysed trend: columns + one row per **qualifying** metric.
class VitalsTrendResult {
  const VitalsTrendResult({
    required this.columns,
    required this.metrics,
    required this.show,
  });

  final List<VitalsTrendColumn> columns;

  /// Only metrics that meet the show rules (never placeholder / flat rows).
  final List<VitalMetricTrend> metrics;

  /// True when the card should be shown (at least one qualifying metric).
  final bool show;

  static const empty = VitalsTrendResult(columns: [], metrics: [], show: false);
}

/// Ordinal ranking for urine-protein grades so they can be displayed.
/// Returns `null` for unrecognised / missing grades.
int? urineProteinRank(String? grade) {
  switch (grade?.toLowerCase().trim()) {
    case 'absent':
    case 'negative':
    case 'neg':
    case 'nil':
      return 0;
    case 'trace':
      return 1;
    case 'present':
    case 'positive':
    case 'pos':
    case '+':
    case '++':
    case '+++':
      return 2;
    default:
      return null;
  }
}

/// True when [grade] is Urinary Albumin / urine protein **Present**
/// (Trace and Absent do not count).
bool isUrineProteinPresent(String? grade) {
  switch (grade?.toLowerCase().trim()) {
    case 'present':
    case 'positive':
    case 'pos':
    case '+':
    case '++':
    case '+++':
      return true;
    default:
      return false;
  }
}

/// Stateless rule engine that turns a visit sequence into a [VitalsTrendResult].
abstract final class VitalsTrendAnalyzer {
  VitalsTrendAnalyzer._();

  /// True when systolic and/or diastolic qualify as a rising AI-trend signal
  /// (same rules as [analyze] — last 2 priors + today, ≥5 each step).
  ///
  /// Used by ANC auto-referral; weight / urine rows do not trigger referral.
  static bool hasRisingBpTrend({
    required List<VisitVitals> priorVisits,
    required VisitVitals today,
  }) {
    final result = analyze(priorVisits: priorVisits, today: today);
    return result.metrics.any(
      (m) =>
          m.rising &&
          (m.metric == VitalMetric.systolic ||
              m.metric == VitalMetric.diastolic),
    );
  }

  /// Analyse [priorVisits] (oldest-first) plus the in-progress [today] snapshot.
  ///
  /// Requires **two** prior visits in the window. Each metric is included only
  /// when its own show rule passes; [VitalsTrendResult.show] is true when the
  /// metrics list is non-empty.
  static VitalsTrendResult analyze({
    required List<VisitVitals> priorVisits,
    required VisitVitals today,
    DateTime? todayDate,
  }) {
    final priors = priorVisits.where((v) => !v.isEmpty).toList();
    // Keep at most the two most recent prior visits (past 2 + today).
    final trimmedPriors =
        priors.length > 2 ? priors.sublist(priors.length - 2) : priors;

    // Need exactly two priors so every parameter can have three readings.
    if (trimmedPriors.length < 2) return VitalsTrendResult.empty;

    final sequence = <VisitVitals>[...trimmedPriors, today];
    final now = todayDate ?? DateTime.now();

    final columns = <VitalsTrendColumn>[
      for (var i = 0; i < trimmedPriors.length; i++)
        VitalsTrendColumn(
          isToday: false,
          visitNumber: i + 1,
          daysAgo: trimmedPriors[i].date == null
              ? null
              : now.difference(trimmedPriors[i].date!).inDays,
        ),
      const VitalsTrendColumn(isToday: true),
    ];

    final metrics = <VitalMetricTrend>[
      ?_numericTrend(
        VitalMetric.systolic,
        sequence.map((v) => v.systolic?.toDouble()).toList(),
      ),
      ?_numericTrend(
        VitalMetric.diastolic,
        sequence.map((v) => v.diastolic?.toDouble()).toList(),
      ),
      ?_numericTrend(
        VitalMetric.weight,
        sequence.map((v) => v.weight).toList(),
      ),
      ?_urineTrend(sequence.map((v) => v.urineProtein).toList()),
    ];

    return VitalsTrendResult(
      columns: columns,
      metrics: metrics,
      show: metrics.isNotEmpty,
    );
  }

  /// Numeric row (sys / dia / weight): 3 readings + rising ≥ [kVitalsTrendMinStep]
  /// on each consecutive step. Otherwise omitted.
  static VitalMetricTrend? _numericTrend(VitalMetric metric, List<double?> raw) {
    if (raw.length < 3) return null;
    if (raw.any((v) => v == null)) return null;
    final values = raw.cast<double>();
    if (!_isRisingByMinStep(values)) return null;
    return VitalMetricTrend(
      metric: metric,
      values: values,
      rising: true,
    );
  }

  /// Urine protein row: 3 captured grades + at least one Present.
  static VitalMetricTrend? _urineTrend(List<String?> grades) {
    if (grades.length < 3) return null;
    final ranks = <num?>[];
    for (final g in grades) {
      final rank = urineProteinRank(g);
      if (rank == null) return null; // missing / unrecognised → not 3 captured
      ranks.add(rank);
    }
    if (!grades.any(isUrineProteinPresent)) return null;
    return VitalMetricTrend(
      metric: VitalMetric.urineProtein,
      values: ranks,
      rising: true,
    );
  }

  /// Each consecutive step must rise by at least [kVitalsTrendMinStep].
  static bool _isRisingByMinStep(
    List<double> values, {
    double minStep = kVitalsTrendMinStep,
  }) {
    if (values.length < 3) return false;
    for (var i = 1; i < values.length; i++) {
      if (values[i] - values[i - 1] < minStep) return false;
    }
    return true;
  }
}
