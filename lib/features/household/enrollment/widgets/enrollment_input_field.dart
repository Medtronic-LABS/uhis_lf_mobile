import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';

/// Styled text input for enrollment forms.
///
/// Renders an 11px gray w700 label (with red `*` if [isRequired]) above a
/// white 12px-radius container with 1.5px #E5E7EB border that switches to
/// 1.5px navy on focus.
///
/// Accepts either a [controller] (preferred for programmatic control) or an
/// [initialValue] (creates an internal controller pre-seeded with the value).
/// Supply [readOnly] for auto-generated / date-picker fields. Use
/// [customBorderColor] and [customFillColor] to override colours for
/// special-case inputs (e.g. the auto-generated household number).
class EnrollmentInputField extends StatefulWidget {
  const EnrollmentInputField({
    required this.label,
    this.hint,
    this.initialValue,
    this.controller,
    this.onChanged,
    this.onBlur,
    this.isRequired = false,
    this.maxLines = 1,
    this.minLines = 1,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.readOnly = false,
    this.customBorderColor,
    this.customFillColor,
    this.customTextColor,
    this.labelSuffix,
    this.inputFormatters,
    super.key,
  });

  final String label;
  final String? hint;
  final String? initialValue;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onBlur;
  final bool isRequired;
  final int maxLines;
  final int minLines;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final bool readOnly;
  final List<TextInputFormatter>? inputFormatters;

  /// Override the border colour (used by auto-generated field: #A7F3D0).
  final Color? customBorderColor;

  /// Override the fill colour (used by auto-generated field: #ECFDF5).
  final Color? customFillColor;

  /// Override the text colour (used by auto-generated field: #059669).
  final Color? customTextColor;

  /// Small suffix appended to the label row (e.g. "(auto-generated)").
  final Widget? labelSuffix;

  @override
  State<EnrollmentInputField> createState() => _EnrollmentInputFieldState();
}

class _EnrollmentInputFieldState extends State<EnrollmentInputField> {
  late TextEditingController _controller;
  bool _hasFocus = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ??
        TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _validateOnBlur() {
    if (widget.validator != null) {
      final error = widget.validator!(_controller.text);
      setState(() => _error = error);
    }
    widget.onBlur?.call();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _error != null
        ? AppColors.statusCritical
        : widget.customBorderColor != null
            ? widget.customBorderColor!
            : _hasFocus
                ? AppColors.navy
                : AppColors.border;

    final fillColor = widget.customFillColor ?? AppColors.cardSurface;
    final textColor = widget.customTextColor ?? AppColors.textPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            if (widget.isRequired)
              const Padding(
                padding: EdgeInsets.only(left: 3),
                child: Text(
                  '*',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.statusCritical,
                  ),
                ),
              ),
            if (widget.labelSuffix != null) ...[
              const SizedBox(width: 6),
              widget.labelSuffix!,
            ],
          ],
        ),
        const SizedBox(height: 6),
        Focus(
          onFocusChange: (hasFocus) {
            setState(() => _hasFocus = hasFocus);
            if (!hasFocus) _validateOnBlur();
          },
          child: Container(
            decoration: BoxDecoration(
              color: fillColor,
              border: Border.all(color: borderColor, width: 1.5),
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: TextField(
              controller: _controller,
              readOnly: widget.readOnly,
              onChanged: (value) {
                setState(() => _error = null);
                widget.onChanged?.call(value);
              },
              maxLines: widget.maxLines,
              minLines: widget.minLines,
              keyboardType: widget.keyboardType,
              inputFormatters: widget.inputFormatters,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
                contentPadding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxxl,
                  AppSpacing.xl,
                  AppSpacing.xxxl,
                  AppSpacing.xl,
                ),
                border: InputBorder.none,
              ),
              style: TextStyle(
                fontSize: 14,
                fontWeight: widget.customTextColor != null
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: textColor,
              ),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.statusCritical,
            ),
          ),
        ],
      ],
    );
  }
}
