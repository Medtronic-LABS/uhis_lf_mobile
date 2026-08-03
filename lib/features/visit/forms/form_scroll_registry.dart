import 'package:flutter/material.dart';

import 'unified_section_rules.dart';

/// Maps validation error field ids to scrollable widgets and scrolls to the
/// first error in document order.
///
/// Composite fields (BP pair, blood-glucose card, supplement pairs, etc.)
/// register one [GlobalKey] on the driver widget and alias absorbed field ids
/// to that owner so scroll targets match what the SK actually sees.
class FormFieldScrollRegistry {
  FormFieldScrollRegistry();

  final Map<String, GlobalKey> _keys = {};
  final Map<String, String> _aliasToOwner = {};

  /// Static fallbacks for composite ids — used before/without build registration.
  static const Map<String, String> staticAliases = {
    'diastolic': 'systolic',
    'bloodPressure': 'systolic',
    'pulse': 'systolic',
    'glucose': 'glucoseType',
    'bloodSugar': 'glucoseType',
    'ancBloodGlucose': 'glucoseType',
    'randomBloodSugar': 'fastingBloodSugar',
    'weight': 'height',
    'bmi': 'height',
  };

  GlobalKey keyFor(String ownerFieldId) =>
      _keys.putIfAbsent(ownerFieldId, GlobalKey.new);

  /// Associates [aliasIds] with [ownerFieldId] for scroll resolution.
  void registerScrollTarget({
    required String ownerFieldId,
    required Set<String> aliasIds,
  }) {
    for (final id in aliasIds) {
      _aliasToOwner[id] = ownerFieldId;
    }
    // Owner scrolls to itself.
    _aliasToOwner[ownerFieldId] = ownerFieldId;
  }

  /// Resolves a validation error id to the widget owner id.
  String resolveOwner(String errorId) {
    if (errorId.startsWith('newbornDetails_')) {
      final parts = errorId.split('_');
      if (parts.length >= 3 && int.tryParse(parts[1]) != null) {
        return 'newbornDetails_${parts[1]}';
      }
    }
    if (errorId == 'newbornDetails') return 'newbornDetails';
    return _aliasToOwner[errorId] ?? staticAliases[errorId] ?? errorId;
  }

  BuildContext? contextForError(String errorId) =>
      keyFor(resolveOwner(errorId)).currentContext;

  /// First error id in the same order sections render (top → bottom).
  String? firstErrorInDocumentOrder(
    Set<String> errors,
    List<AnnotatedFormSection> annotated,
  ) {
    if (errors.isEmpty) return null;

    for (final a in annotated) {
      if (a.section.sectionId == 'newbornDetails' &&
          a.section.formType == 'pregnancyOutcome') {
        if (errors.contains('newbornDetails')) return 'newbornDetails';
        for (final e in errors) {
          if (e.startsWith('newbornDetails_')) return e;
        }
        continue;
      }

      for (final ref in a.section.fieldRefs) {
        if (errors.contains(ref.id)) return ref.id;
        for (final e in errors) {
          if (resolveOwner(e) == ref.id) return e;
        }
      }
    }

    for (final e in errors) {
      if (e.startsWith('newbornDetails')) return e;
    }
    return errors.first;
  }

  String? sectionKeyForError(
    String errorId,
    List<AnnotatedFormSection> annotated,
  ) {
    for (final a in annotated) {
      if (a.section.sectionId == 'newbornDetails' &&
          a.section.formType == 'pregnancyOutcome' &&
          errorId.startsWith('newbornDetails')) {
        return '${a.section.formType}_${a.section.sectionId}';
      }
      if (a.section.fieldRefs.any((r) => r.id == resolveOwner(errorId))) {
        return '${a.section.formType}_${a.section.sectionId}';
      }
      if (a.section.fieldRefs.any((r) => r.id == errorId)) {
        return '${a.section.formType}_${a.section.sectionId}';
      }
    }
    return null;
  }
}

/// Wraps a rendered field (or composite card) with a [GlobalKey] used for
/// [Scrollable.ensureVisible] on validation failure.
class FormScrollTarget extends StatelessWidget {
  const FormScrollTarget({
    super.key,
    required this.registry,
    required this.ownerFieldId,
    required this.aliasIds,
    required this.child,
  });

  final FormFieldScrollRegistry registry;
  final String ownerFieldId;
  final Set<String> aliasIds;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    registry.registerScrollTarget(
      ownerFieldId: ownerFieldId,
      aliasIds: aliasIds,
    );
    return KeyedSubtree(
      key: registry.keyFor(ownerFieldId),
      child: child,
    );
  }
}

/// Scrolls to the first validation error after the error-highlight rebuild.
class FormScrollHelper {
  FormScrollHelper._();

  static const _maxAttempts = 3;
  static const _scrollDuration = Duration(milliseconds: 350);

  static void scrollToFirstError({
    required BuildContext context,
    required FormFieldScrollRegistry registry,
    required List<AnnotatedFormSection> annotated,
    required Set<String> errors,
    required Map<String, GlobalKey> sectionKeys,
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || errors.isEmpty) return;

      final errorId =
          registry.firstErrorInDocumentOrder(errors, annotated);
      if (errorId == null) return;

      final fieldCtx = registry.contextForError(errorId);
      if (fieldCtx != null) {
        _ensureVisible(fieldCtx);
        return;
      }

      final sectionKeyId =
          registry.sectionKeyForError(errorId, annotated);
      if (sectionKeyId != null) {
        final sectionCtx = sectionKeys[sectionKeyId]?.currentContext;
        if (sectionCtx != null) {
          _ensureVisible(sectionCtx);
          return;
        }
      }

      if (attempt + 1 < _maxAttempts) {
        scrollToFirstError(
          context: context,
          registry: registry,
          annotated: annotated,
          errors: errors,
          sectionKeys: sectionKeys,
          attempt: attempt + 1,
        );
      } else {
        debugPrint(
          '[FormScroll] could not scroll to error "$errorId" '
          '(owner=${registry.resolveOwner(errorId)}) after $_maxAttempts frames',
        );
      }
    });
  }

  static void _ensureVisible(BuildContext ctx) {
    Scrollable.ensureVisible(
      ctx,
      duration: _scrollDuration,
      curve: Curves.easeOut,
      alignment: 0.12,
    );
    // Dismiss keyboard after scroll so the target field stays in view.
    FocusManager.instance.primaryFocus?.unfocus();
  }
}
