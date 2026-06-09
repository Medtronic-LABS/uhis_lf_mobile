import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../scribe_controller.dart';
import '../models/ai_extracted_field.dart';
import 'ai_field_indicator.dart';

/// A text form field that can be auto-populated by AI scribe.
///
/// Displays an AI indicator when the field has been populated by AI,
/// and provides accept/reject controls for the user to review.
class AITextFormField extends StatefulWidget {
  const AITextFormField({
    super.key,
    required this.fieldId,
    required this.controller,
    this.decoration,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
  });

  /// Field ID matching the FormFieldSchema sent to AI scribe.
  final String fieldId;

  /// Text controller for the field.
  final TextEditingController controller;

  /// Input decoration for the field.
  final InputDecoration? decoration;

  /// Keyboard type for the field.
  final TextInputType? keyboardType;

  /// Validator for the field.
  final FormFieldValidator<String>? validator;

  /// Called when the field value changes.
  final ValueChanged<String>? onChanged;

  /// Whether the field is enabled.
  final bool enabled;

  /// Whether the field is read-only.
  final bool readOnly;

  /// Maximum number of lines for the field.
  final int maxLines;

  @override
  State<AITextFormField> createState() => _AITextFormFieldState();
}

class _AITextFormFieldState extends State<AITextFormField> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ScribeController>(
      builder: (context, scribeCtrl, _) {
        final aiField = scribeCtrl.getField(widget.fieldId);

        // Apply AI value if pending and controller is empty
        if (aiField != null &&
            aiField.source == FieldSource.aiPending &&
            widget.controller.text.isEmpty &&
            aiField.value != null) {
          // Set controller value without triggering onChanged
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && widget.controller.text.isEmpty) {
              widget.controller.text = aiField.value.toString();
            }
          });
        }

        final textField = TextFormField(
          controller: widget.controller,
          decoration: widget.decoration,
          keyboardType: widget.keyboardType,
          validator: widget.validator,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          maxLines: widget.maxLines,
          onChanged: (value) {
            // If user manually modifies an AI field, mark it as modified
            if (aiField != null && aiField.source == FieldSource.aiPending) {
              scribeCtrl.modifyField(widget.fieldId, value);
            }
            widget.onChanged?.call(value);
          },
        );

        if (aiField == null) {
          return textField;
        }

        return AIFieldWrapper(
          aiField: aiField,
          onAccept: () => scribeCtrl.acceptField(widget.fieldId),
          onReject: () {
            scribeCtrl.rejectField(widget.fieldId);
            widget.controller.clear();
          },
          onEdit: () {
            // Focus the field for editing
          },
          child: textField,
        );
      },
    );
  }
}

/// A checkbox that can be auto-populated by AI scribe.
class AICheckboxFormField extends StatelessWidget {
  const AICheckboxFormField({
    super.key,
    required this.fieldId,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
  });

  final String fieldId;
  final bool value;
  final ValueChanged<bool?> onChanged;
  final Widget title;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    return Consumer<ScribeController>(
      builder: (context, scribeCtrl, _) {
        final aiField = scribeCtrl.getField(fieldId);

        // Use AI value if pending
        final effectiveValue = aiField != null &&
                aiField.source == FieldSource.aiPending &&
                aiField.value is bool
            ? aiField.value as bool
            : value;

        final checkbox = CheckboxListTile(
          value: effectiveValue,
          onChanged: (newValue) {
            // If user manually changes an AI field, mark it as modified
            if (aiField != null && aiField.source == FieldSource.aiPending) {
              scribeCtrl.modifyField(fieldId, newValue);
            }
            onChanged(newValue);
          },
          title: title,
          subtitle: subtitle,
          controlAffinity: ListTileControlAffinity.leading,
        );

        if (aiField == null) {
          return checkbox;
        }

        return AIFieldWrapper(
          aiField: aiField,
          onAccept: () => scribeCtrl.acceptField(fieldId),
          onReject: () {
            scribeCtrl.rejectField(fieldId);
            onChanged(false);
          },
          child: checkbox,
        );
      },
    );
  }
}

/// A dropdown that can be auto-populated by AI scribe.
class AIDropdownFormField<T> extends StatelessWidget {
  const AIDropdownFormField({
    super.key,
    required this.fieldId,
    required this.value,
    required this.items,
    required this.onChanged,
    this.decoration,
    this.hint,
  });

  final String fieldId;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final InputDecoration? decoration;
  final Widget? hint;

  @override
  Widget build(BuildContext context) {
    return Consumer<ScribeController>(
      builder: (context, scribeCtrl, _) {
        final aiField = scribeCtrl.getField(fieldId);

        // Use AI value if pending and matches type
        final effectiveValue = aiField != null &&
                aiField.source == FieldSource.aiPending &&
                aiField.value is T
            ? aiField.value as T
            : value;

        final dropdown = DropdownButtonFormField<T>(
          value: effectiveValue,
          items: items,
          onChanged: (newValue) {
            // If user manually changes an AI field, mark it as modified
            if (aiField != null && aiField.source == FieldSource.aiPending) {
              scribeCtrl.modifyField(fieldId, newValue);
            }
            onChanged(newValue);
          },
          decoration: decoration,
          hint: hint,
        );

        if (aiField == null) {
          return dropdown;
        }

        return AIFieldWrapper(
          aiField: aiField,
          onAccept: () => scribeCtrl.acceptField(fieldId),
          onReject: () {
            scribeCtrl.rejectField(fieldId);
            onChanged(null);
          },
          child: dropdown,
        );
      },
    );
  }
}

/// Extension to easily get AI field values from a ScribeController.
extension AIFieldExtension on ScribeController {
  /// Get string value for a field, or null if not extracted or rejected.
  String? getStringValue(String fieldId) {
    final field = getField(fieldId);
    if (field == null || field.source == FieldSource.aiRejected) return null;
    return field.value?.toString();
  }

  /// Get bool value for a field, or null if not extracted or rejected.
  bool? getBoolValue(String fieldId) {
    final field = getField(fieldId);
    if (field == null || field.source == FieldSource.aiRejected) return null;
    return field.value is bool ? field.value as bool : null;
  }

  /// Get double value for a field, or null if not extracted or rejected.
  double? getDoubleValue(String fieldId) {
    final field = getField(fieldId);
    if (field == null || field.source == FieldSource.aiRejected) return null;
    if (field.value is double) return field.value as double;
    if (field.value is int) return (field.value as int).toDouble();
    if (field.value is String) return double.tryParse(field.value as String);
    return null;
  }

  /// Get int value for a field, or null if not extracted or rejected.
  int? getIntValue(String fieldId) {
    final field = getField(fieldId);
    if (field == null || field.source == FieldSource.aiRejected) return null;
    if (field.value is int) return field.value as int;
    if (field.value is double) return (field.value as double).round();
    if (field.value is String) return int.tryParse(field.value as String);
    return null;
  }
}

/// Mixin for forms that support AI scribe field population.
mixin AIFormMixin<T extends StatefulWidget> on State<T> {
  /// Apply AI-extracted values to form controllers.
  ///
  /// Call this in initState or when AI results become available.
  void applyAIValues(ScribeController scribeCtrl, Map<String, TextEditingController> controllers) {
    final result = scribeCtrl.session.formPrefillResult;
    if (result == null) return;

    for (final field in result.fields) {
      final controller = controllers[field.fieldId];
      if (controller != null && field.value != null && field.source != FieldSource.aiRejected) {
        controller.text = field.value.toString();
      }
    }
  }

  /// Build an audit map of AI vs manual field sources for saving.
  Map<String, dynamic> buildAuditMap(ScribeController scribeCtrl) {
    return {
      'aiAssisted': scribeCtrl.session.hasFormPrefillResult,
      'fields': scribeCtrl.getAuditTrail(),
      'sessionId': scribeCtrl.session.noteId,
    };
  }
}
