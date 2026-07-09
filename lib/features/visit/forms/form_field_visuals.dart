import 'package:flutter/material.dart';

/// Decorative glyph + pastel tile colour shown on the left of a form field's
/// icon card.  This is purely structural presentation metadata (not localizable
/// user copy), keyed by field id, mirroring the `apon_sushashthya` v13 mockup.
class FieldGlyph {
  const FieldGlyph(this.emoji, this.background);

  /// The emoji rendered inside the rounded tile (e.g. `🩺`).
  final String emoji;

  /// Pastel tile background behind the emoji.
  final Color background;
}

/// Maps a field id to the icon-card glyph used by the Step 2 unified form.
///
/// Fields without a dedicated glyph render as a plain card (no tile), matching
/// the mockup's "Urine tests" / free-text blocks, so unmapped fields degrade
/// gracefully rather than showing a placeholder icon.
abstract final class FormFieldVisuals {
  FormFieldVisuals._();

  // Pastel tile backgrounds (from the v13 mockup's vitals cards).
  static const Color _indigo = Color(0xFFEEF0FF);
  static const Color _green = Color(0xFFF0FDF4);
  static const Color _amber = Color(0xFFFEF3C7);
  static const Color _pink = Color(0xFFFDF2F8);
  static const Color _red = Color(0xFFFEE2E2);
  static const Color _blue = Color(0xFFEFF6FF);

  static const Map<String, FieldGlyph> _byId = {
    // Cardio / BP
    'bloodPressure': FieldGlyph('🩺', _indigo),
    'systolic': FieldGlyph('🩺', _indigo),
    'diastolic': FieldGlyph('🩺', _indigo),
    'pulse': FieldGlyph('💓', _red),
    'temperature': FieldGlyph('🌡️', _amber),
    // Anthropometry
    'weight': FieldGlyph('⚖️', _green),
    'height': FieldGlyph('📐', _indigo),
    'bmi': FieldGlyph('📊', _blue),
    // Maternal
    'fundalHeight': FieldGlyph('📏', _pink),
    'fetalMovement': FieldGlyph('👶', _green),
    // Urine dipstick
    'urinaryAlbumin': FieldGlyph('🧪', _amber),
    'urinarySugar': FieldGlyph('🧪', _amber),
    'urinaryBilirubin': FieldGlyph('🧪', _amber),
    // Blood tests
    'hemoglobin': FieldGlyph('🩸', _red),
    'bloodSugar': FieldGlyph('🩸', _red),
    'bloodSugarFasting': FieldGlyph('🩸', _red),
    'bloodSugarRandom': FieldGlyph('🩸', _red),
    'fastingBloodSugar': FieldGlyph('🩸', _red),
    'randomBloodSugar': FieldGlyph('🩸', _red),
    'ancBloodGlucose': FieldGlyph('🩸', _red),
    'glucose': FieldGlyph('🩸', _red),
  };

  /// Returns the glyph for [fieldId], or `null` when the field has no dedicated
  /// icon and should render as a plain card.
  static FieldGlyph? forField(String fieldId) => _byId[fieldId];
}
