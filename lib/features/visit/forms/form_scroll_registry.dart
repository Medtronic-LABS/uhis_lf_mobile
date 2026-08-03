import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'unified_section_rules.dart';

/// Maps validation error field ids to scrollable widgets and scrolls to the
/// first error in document order.
///
/// Keys are scoped by [formType] so the same field id in ANC + NCD never
/// shares one [GlobalKey] (which breaks [GlobalKey.currentContext]).
class FormFieldScrollRegistry {
  FormFieldScrollRegistry();

  final Map<String, GlobalKey> _keys = {};
  final Map<String, String> _aliasToOwner = {};

  /// Static fallbacks for composite ids — scoped per programme at resolve time.
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

  static String scopedKey(String formType, String fieldId) => '$formType:$fieldId';

  GlobalKey keyFor(String scopedOwnerId) =>
      _keys.putIfAbsent(scopedOwnerId, GlobalKey.new);

  /// Associates scoped [aliasIds] with a scoped [ownerFieldId].
  void registerScrollTarget({
    required String ownerFieldId,
    required Set<String> aliasIds,
  }) {
    for (final id in aliasIds) {
      _aliasToOwner[id] = ownerFieldId;
    }
    _aliasToOwner[ownerFieldId] = ownerFieldId;
  }

  /// Resolves a validation error id to a scoped scroll-owner id.
  String resolveOwner(String errorId, {required String formType}) {
    if (errorId.contains(':')) return errorId;

    if (errorId.startsWith('newbornDetails_')) {
      final parts = errorId.split('_');
      if (parts.length >= 3 && int.tryParse(parts[1]) != null) {
        return scopedKey(formType, 'newbornDetails_${parts[1]}');
      }
    }
    if (errorId == 'newbornDetails') {
      return scopedKey(formType, 'newbornDetails');
    }

    final scopedError = scopedKey(formType, errorId);
    if (_aliasToOwner.containsKey(scopedError)) {
      return _aliasToOwner[scopedError]!;
    }

    final driver = staticAliases[errorId];
    if (driver != null) {
      final scopedDriver = scopedKey(formType, driver);
      if (_aliasToOwner.containsKey(scopedDriver)) {
        return _aliasToOwner[scopedDriver]!;
      }
      return scopedDriver;
    }

    return scopedKey(formType, errorId);
  }

  /// Returns context for an already-registered scoped owner — never creates keys.
  BuildContext? contextForOwner(String scopedOwnerId) =>
      _keys[scopedOwnerId]?.currentContext;

  /// First scoped scroll-owner id in document order (top → bottom).
  String? firstErrorInDocumentOrder(
    Set<String> errors,
    List<AnnotatedFormSection> annotated,
  ) {
    if (errors.isEmpty) return null;

    for (final a in annotated) {
      final formType = a.section.formType;

      if (a.section.sectionId == 'newbornDetails' &&
          a.section.formType == 'pregnancyOutcome') {
        if (errors.contains('newbornDetails')) {
          return scopedKey(formType, 'newbornDetails');
        }
        for (final e in errors) {
          if (e.startsWith('newbornDetails_')) {
            return resolveOwner(e, formType: formType);
          }
        }
        continue;
      }

      for (final ref in a.section.fieldRefs) {
        final owner = scopedKey(formType, ref.id);
        if (errors.contains(ref.id)) return owner;
        for (final e in errors) {
          if (resolveOwner(e, formType: formType) == owner) return owner;
        }
      }
    }

    for (final e in errors) {
      if (e.startsWith('newbornDetails')) {
        for (final a in annotated) {
          if (a.section.sectionId == 'newbornDetails') {
            return resolveOwner(e, formType: a.section.formType);
          }
        }
      }
    }
    return null;
  }

  String? sectionKeyForOwner(
    String scopedOwnerId,
    List<AnnotatedFormSection> annotated,
  ) {
    final colon = scopedOwnerId.indexOf(':');
    if (colon <= 0) return null;
    final formType = scopedOwnerId.substring(0, colon);
    final fieldId = scopedOwnerId.substring(colon + 1);

    for (final a in annotated) {
      if (a.section.formType != formType) continue;

      if (a.section.sectionId == 'newbornDetails' &&
          fieldId.startsWith('newbornDetails')) {
        return '${a.section.formType}_${a.section.sectionId}';
      }

      if (a.section.fieldRefs.any((r) => r.id == fieldId)) {
        return '${a.section.formType}_${a.section.sectionId}';
      }

      for (final ref in a.section.fieldRefs) {
        if (resolveOwner(fieldId, formType: formType) ==
            scopedKey(formType, ref.id)) {
          return '${a.section.formType}_${a.section.sectionId}';
        }
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
    required this.formType,
    required this.registry,
    required this.ownerFieldId,
    required this.aliasIds,
    required this.child,
  });

  final String formType;
  final FormFieldScrollRegistry registry;
  final String ownerFieldId;
  final Set<String> aliasIds;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final owner = FormFieldScrollRegistry.scopedKey(formType, ownerFieldId);
    final aliases = aliasIds
        .map((id) => FormFieldScrollRegistry.scopedKey(formType, id))
        .toSet()
      ..add(owner);

    registry.registerScrollTarget(
      ownerFieldId: owner,
      aliasIds: aliases,
    );

    return KeyedSubtree(
      key: registry.keyFor(owner),
      child: child,
    );
  }
}

/// Scrolls to the first validation error after the error-highlight rebuild.
class FormScrollHelper {
  FormScrollHelper._();

  static const _maxAttempts = 4;
  static const _scrollDuration = Duration(milliseconds: 350);
  static const _alignment = 0.12;

  static void scrollToFirstError({
    required BuildContext context,
    required FormFieldScrollRegistry registry,
    required List<AnnotatedFormSection> annotated,
    required Set<String> errors,
    required Map<String, GlobalKey> sectionKeys,
    ScrollController? scrollController,
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || errors.isEmpty) return;

      final scopedOwner =
          registry.firstErrorInDocumentOrder(errors, annotated);
      if (scopedOwner == null) {
        debugPrint('[FormScroll] no scroll target for errors: $errors');
        return;
      }

      final fieldCtx = registry.contextForOwner(scopedOwner);
      if (fieldCtx != null &&
          _scrollToContext(fieldCtx, scrollController: scrollController)) {
        FocusManager.instance.primaryFocus?.unfocus();
        debugPrint('[FormScroll] scrolled to field $scopedOwner');
        return;
      }

      final sectionKeyId =
          registry.sectionKeyForOwner(scopedOwner, annotated);
      if (sectionKeyId != null) {
        final sectionCtx = sectionKeys[sectionKeyId]?.currentContext;
        if (sectionCtx != null &&
            _scrollToContext(sectionCtx,
                scrollController: scrollController)) {
          FocusManager.instance.primaryFocus?.unfocus();
          debugPrint('[FormScroll] scrolled to section $sectionKeyId '
              '(field $scopedOwner)');
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
          scrollController: scrollController,
          attempt: attempt + 1,
        );
      } else {
        debugPrint(
          '[FormScroll] could not scroll to "$scopedOwner" '
          'after $_maxAttempts frames (errors=$errors)',
        );
      }
    });
  }

  static bool _scrollToContext(
    BuildContext ctx, {
    ScrollController? scrollController,
  }) {
    final renderObject = ctx.findRenderObject();
    if (renderObject == null || !renderObject.attached) return false;

    if (scrollController != null && scrollController.hasClients) {
      try {
        final viewport = RenderAbstractViewport.of(renderObject);
        final target = viewport.getOffsetToReveal(renderObject, _alignment);
        final max = scrollController.position.maxScrollExtent;
        scrollController.animateTo(
          target.offset.clamp(0.0, max),
          duration: _scrollDuration,
          curve: Curves.easeOut,
        );
        return true;
      } catch (_) {
        // Fall through to ensureVisible.
      }
    }

    Scrollable.ensureVisible(
      ctx,
      duration: _scrollDuration,
      curve: Curves.easeOut,
      alignment: _alignment,
    );
    return true;
  }
}
