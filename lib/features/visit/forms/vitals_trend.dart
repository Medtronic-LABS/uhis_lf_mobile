t/// Pure-Dart rule-based trend detection across a patient's ANC visits.
///
/// No Flutter dependencies and no user-facing strings — this is the business
/// logic behind the "AI sees a trend across her N visits" card.  The rule is
/// intentionally simple and explainable (no ML): a metric is *rising* when its
/// values are non-decreasing across the visit sequence and strictly higher at
/// the latest reading than at the earliest.  The card surfaces whenever blood
/// pressure (systolic OR diastolic) is rising, so the SK sees a multi-visit
/// climb even when no single reading has yet crossed an alert threshold.
///
/// All display formatting (column titles, urine-grade labels, footer copy)
/// lives in the widget layer via `UnifiedFormStrings`; this file only compares
/// numbers and returns booleans + raw values.
library;

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

  /// True when this metric is climbing across the sequence.
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

/// The full analysed trend: columns + one row per metric that has data.
class VitalsTrendResult {
  const VitalsTrendResult({
    required this.columns,
    required this.metrics,
    required this.show,
  });

  final List<VitalsTrendColumn> columns;
  final List<VitalMetricTrend> metrics;

  /// True when the card should be shown (BP rising across ≥2 data points).
  final bool show;

  static const empty = VitalsTrendResult(columns: [], metrics: [], show: false);
}

/// Ordinal ranking for urine-protein grades so they can be compared.
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

/// Stateless rule engine that turns a visit sequence into a [VitalsTrendResult].
abstract final class VitalsTrendAnalyzer {
  VitalsTrendAnalyzer._();

  /// Analyse [priorVisits] (oldest-first) plus the in-progress [today] snapshot.
  ///
  /// The card is shown only when at least two BP data points exist and either
  /// systolic or diastolic is rising.  Weight and urine-protein rows are
  /// included for context whenever they have data, but they never — on their
  /// own — trigger the card.
  static VitalsTrendResult analyze({
    required List<VisitVitals> priorVisits,
    required VisitVitals today,
    DateTime? todayDate,
  }) {
    final priors = priorVisits.where((v) => !v.isEmpty).toList();
    // Keep at most the two most recent prior visits so the table stays to
    // three columns like the reference design.
    final trimmedPriors =
        priors.length > 2 ? priors.sublist(priors.length - 2) : priors;

    // Need at least one prior + today to describe any movement.
    if (trimmedPriors.isEmpty) return VitalsTrendResult.empty;

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

    final systolic = _numericTrend(
      VitalMetric.systolic,
      sequence.map((v) => v.systolic?.toDouble()).toList(),
    );
    final diastolic = _numericTrend(
      VitalMetric.diastolic,
      sequence.map((v) => v.diastolic?.toDouble()).toList(),
    );
    final weight = _numericTrend(
      VitalMetric.weight,
      sequence.map((v) => v.weight).toList(),
    );
    final urine = _numericTrend(
      VitalMetric.urineProtein,
      sequence.map((v) => urineProteinRank(v.urineProtein)?.toDouble()).toList(),
    );

    final metrics = <VitalMetricTrend>[
      ?systolic,
      ?diastolic,
      ?weight,
      ?urine,
    ];

    final bpRising =
        (systolic?.rising ?? false) || (diastolic?.rising ?? false);

    return VitalsTrendResult(
      columns: columns,
      metrics: metrics,
      show: bpRising && metrics.isNotEmpty,
    );
  }

  /// Builds a metric trend, or `null` when fewer than two readings exist
  /// (not enough to describe movement).
  static VitalMetricTrend? _numericTrend(VitalMetric metric, List<double?> raw) {
    final present = raw.whereType<double>().toList();
    if (present.length < 2) return null;
    return VitalMetricTrend(
      metric: metric,
      values: raw,
      rising: _isRising(present),
    );
  }

  /// A series is "rising" when it never decreases step-to-step and ends
  /// strictly higher than it started.
  static bool _isRising(List<double> values) {
    if (values.length < 2) return false;
    for (var i = 1; i < values.length; i++) {
      if (values[i] < values[i - 1]) return false;
    }
    return values.last > values.first;
  }
}
