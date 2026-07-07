/// Projects a flat field-value map down to the fields owned by a single
/// programme, using `assets/forms/layout_manifests.json` as ground truth.
///
/// This replaces [SectionRegistry.projectionFor] for SDK-path submissions
/// where field IDs come from `field_library.json` (the canonical backend IDs)
/// rather than the legacy Dart [SectionRegistry] IDs.
///
/// Usage:
///   await SdkFieldProjector.init();          // once at app start
///   final payload = SdkFieldProjector.project(Programme.anc, flatValues);
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../../core/models/programme.dart';

class SdkFieldProjector {
  SdkFieldProjector._();

  /// formTypeId → Set of fieldIds owned by that form (from layout_manifests).
  static final Map<String, Set<String>> _formTypeFields = {};
  static bool _initialized = false;

  /// Must be called once before [project]. Safe to call multiple times.
  static Future<void> init() async {
    if (_initialized) return;
    final raw = await rootBundle
        .loadString('assets/forms/layout_manifests.json');
    final manifests = jsonDecode(raw) as List<dynamic>;
    for (final manifest in manifests.whereType<Map<String, dynamic>>()) {
      final formType = manifest['formType'] as String? ?? '';
      final owned = <String>{};
      for (final sec
          in (manifest['sections'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()) {
        for (final ref
            in (sec['fieldRefs'] as List<dynamic>? ?? [])) {
          final fid = ref is Map<String, dynamic>
              ? ref['id'] as String?
              : ref as String?;
          if (fid != null && fid.isNotEmpty) owned.add(fid);
        }
      }
      _formTypeFields[formType] = owned;
    }
    _initialized = true;
  }

  /// Maps [Programme] → layout_manifests formType ID.
  ///
  /// Mirrors [SdkFormCompositor._formTypeId]; kept here to avoid a circular
  /// dependency between the projector and the compositor.
  static String? _formTypeId(Programme p) => switch (p) {
        Programme.anc => 'anc',
        Programme.ncd => 'ncd',
        Programme.pnc => 'pncMother',
        Programme.tb => 'tb',
        Programme.imci => null,
        Programme.epi => 'epi',
        Programme.nutrition => 'nutrition',
        Programme.familyPlanning => 'family_planning',
        Programme.cataract => 'cataract',
        Programme.eyeCare => 'eye_care',
        Programme.unknown => null,
      };

  /// Project [allFields] to only those owned by [programme] in the manifests.
  ///
  /// Returns an empty map if [programme] has no manifest (e.g. IMCI) or
  /// [init] has not been called.
  static Map<String, dynamic> project(
    Programme programme,
    Map<String, dynamic> allFields,
  ) {
    final ftId = _formTypeId(programme);
    if (ftId == null) return const {};
    final owned = _formTypeFields[ftId];
    if (owned == null || owned.isEmpty) return const {};
    return {
      for (final e in allFields.entries)
        if (owned.contains(e.key)) e.key: e.value,
    };
  }
}
