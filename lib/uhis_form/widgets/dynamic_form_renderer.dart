/// Top-level form widget — renders all sections from a [FormSchema].
///
/// Rebuilds on every [DynamicFormController.notifyListeners] call, hiding or
/// showing fields according to evaluated conditions.
library;

import 'package:flutter/material.dart';

import '../controller/dynamic_form_controller.dart';
import '../models/field_kind.dart';
import '../models/form_schema.dart';
import 'field_renderer.dart';
import 'section_card.dart';

class DynamicFormRenderer extends StatelessWidget {
  const DynamicFormRenderer({
    super.key,
    required this.schema,
    required this.controller,
    this.previousAncWeight,
  });

  final FormSchema schema;
  final DynamicFormController controller;
  final double? previousAncWeight;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final sections = schema.sections
            .where((s) => s.fields.isNotEmpty)
            .toList();

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: sections.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final section = sections[i];
            return SectionCard(
              title: section.title,
              children: section.fields
                  .map((f) => AnimatedSize(
                        key: ValueKey('${section.sectionId}:${f.fieldId}'),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: controller.isVisible(f.fieldId)
                            ? FieldRenderer(
                                schema: f,
                                value: controller.fieldValues[f.fieldId],
                                onChanged: (v) =>
                                    controller.setValue(f.fieldId, v),
                                aiHint: controller.getAiHint(f.fieldId),
                                errorText:
                                    controller.validationErrors[f.fieldId],
                                previousWeight: f.kind == FieldKind.anthropometry
                                    ? previousAncWeight
                                    : null,
                              )
                            : const SizedBox.shrink(),
                      ))
                  .toList(),
            );
          },
        );
      },
    );
  }
}
