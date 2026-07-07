/// Visibility condition parsed from the `condition` array on a source field
/// in program_forms.json.
///
/// JSON shape (one entry in the array):
///   { "targetId": "otherPncNeonateSigns", "eq": "Other", "visibility": "visible" }
///   { "targetId": "randomBloodSugar", "eqList": ["random"], "visibility": "visible" }
///   { "targetId": "parity", "greaterThanOrEqual": "2", "visibility": "visible" }
///   { "targetId": "livingChildren", "lessThanOrEqual": "1", "visibility": "gone" }
///
/// A [ConditionSchema] is stored on the SOURCE [FieldSchema] (the field whose
/// value changes) and names a TARGET field to show or hide.
///
/// [DynamicFormController] inverts this mapping at init time — for each target
/// field it builds a list of conditions that govern its visibility.
library;

/// The comparison operator used by a [ConditionSchema].
enum ConditionOp { eq, eqList, gte, lte }

class ConditionSchema {
  const ConditionSchema({
    required this.targetFieldId,
    required this.op,
    required this.value,
    required this.showTarget,
  });

  factory ConditionSchema.fromJson(Map<String, dynamic> json) {
    final target = json['targetId'] as String;
    final show = (json['visibility'] as String?) != 'gone';

    if (json.containsKey('eq')) {
      return ConditionSchema(
        targetFieldId: target,
        op: ConditionOp.eq,
        value: json['eq'],
        showTarget: show,
      );
    }
    if (json.containsKey('eqList')) {
      return ConditionSchema(
        targetFieldId: target,
        op: ConditionOp.eqList,
        value: List<dynamic>.from(json['eqList'] as List),
        showTarget: show,
      );
    }
    if (json.containsKey('greaterThanOrEqual')) {
      return ConditionSchema(
        targetFieldId: target,
        op: ConditionOp.gte,
        value: json['greaterThanOrEqual'],
        showTarget: show,
      );
    }
    if (json.containsKey('lessThanOrEqual')) {
      return ConditionSchema(
        targetFieldId: target,
        op: ConditionOp.lte,
        value: json['lessThanOrEqual'],
        showTarget: show,
      );
    }
    // Fallback — treat as eq with null value (never hides target)
    return ConditionSchema(
      targetFieldId: target,
      op: ConditionOp.eq,
      value: null,
      showTarget: show,
    );
  }

  /// The field whose visibility this condition controls.
  final String targetFieldId;

  final ConditionOp op;

  /// Comparison value — String, bool, `List<dynamic>`, or null.
  final dynamic value;

  /// When true, the target field becomes visible when the condition holds.
  /// When false, the target field becomes hidden when the condition holds.
  final bool showTarget;

  /// Evaluate against [currentValue] — the current value of the source field.
  bool evaluate(dynamic currentValue) {
    switch (op) {
      case ConditionOp.eq:
        return _looseEq(currentValue, value);
      case ConditionOp.eqList:
        final list = value as List<dynamic>;
        return list.any((v) => _looseEq(currentValue, v));
      case ConditionOp.gte:
        final n = _toNum(currentValue);
        final threshold = _toNum(value);
        if (n == null || threshold == null) return false;
        return n >= threshold;
      case ConditionOp.lte:
        final n = _toNum(currentValue);
        final threshold = _toNum(value);
        if (n == null || threshold == null) return false;
        return n <= threshold;
    }
  }

  static bool _looseEq(dynamic a, dynamic b) {
    if (a == b) return true;
    return a?.toString().toLowerCase() == b?.toString().toLowerCase();
  }

  static num? _toNum(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '');
  }

  @override
  String toString() => 'ConditionSchema($op $value → show=$showTarget $targetFieldId)';
}
