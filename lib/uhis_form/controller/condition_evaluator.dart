/// Pure function: evaluates all conditions in a [FormSchema] against current
/// field values and returns a map of fieldId → isVisible.
///
/// Conditions are stored on SOURCE fields (the field whose value triggers
/// visibility changes). This evaluator inverts that: for each target field it
/// walks every condition in the form and applies the latest result.
///
/// Default visibility: all fields are visible unless a condition sets them gone.
/// If a field has NO conditions that reference it as a target, it stays visible.
/// If it IS a target, the LAST matching condition wins (matching the Android
/// logic that processes conditions in list order).
library;

import '../models/form_schema.dart';

abstract final class ConditionEvaluator {
  ConditionEvaluator._();

  /// Returns fieldId → visible (true = visible, false = hidden).
  static Map<String, bool> evaluate(
    FormSchema schema,
    Map<String, dynamic> fieldValues,
  ) {
    // Start with every field visible.
    final visibility = <String, bool>{
      for (final f in schema.allFields) f.fieldId: true,
    };

    // Walk every source field's conditions.
    for (final sourceField in schema.allFields) {
      for (final cond in sourceField.conditions) {
        final sourceValue = fieldValues[sourceField.fieldId];
        final matches = cond.evaluate(sourceValue);

        // showTarget=true + matches → show target
        // showTarget=false + matches → hide target
        // showTarget=true + !matches → hide target (it should only show when condition holds)
        final targetVisible = cond.showTarget ? matches : !matches;
        visibility[cond.targetFieldId] = targetVisible;
      }
    }

    return visibility;
  }
}
