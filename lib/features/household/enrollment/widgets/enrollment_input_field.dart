import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

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

  @override
  State<EnrollmentInputField> createState() => _EnrollmentInputFieldState();
}

class _EnrollmentInputFieldState extends State<EnrollmentInputField> {
  late TextEditingController _controller;
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
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            if (widget.isRequired)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  '*',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.statusCritical,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            border: Border.all(
              color: _error != null ? AppColors.statusCritical : AppColors.border,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          child: Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus) {
                _validateOnBlur();
              }
            },
            child: TextField(
              controller: _controller,
              onChanged: (value) {
                setState(() => _error = null);
                widget.onChanged?.call(value);
              },
              maxLines: widget.maxLines,
              minLines: widget.minLines,
              keyboardType: widget.keyboardType,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: InputBorder.none,
              ),
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
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
