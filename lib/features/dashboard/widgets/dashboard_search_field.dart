import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../household/enrollment/enrollment_entry_sheet.dart';

/// Inline search field for the Mission Dashboard header.
///
/// Filters the dashboard's own loaded patient queue (by name, mobile, or NID)
/// without opening a full-screen overlay or navigating to the patient page.
/// Calls [onChanged] on every keystroke so the caller can apply the filter
/// synchronously from its cached queue.
class DashboardSearchField extends StatefulWidget {
  const DashboardSearchField({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<DashboardSearchField> createState() => _DashboardSearchFieldState();
}

class _DashboardSearchFieldState extends State<DashboardSearchField> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _ctrl,
        onChanged: widget.onChanged,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: SearchStrings.barHint,
          hintStyle: const TextStyle(
            color: AppColors.textDisabled,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 10, right: 4),
            child: Icon(Icons.search_rounded, color: AppColors.textDisabled, size: 16),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _ctrl,
            builder: (context, value, child) {
              if (value.text.isEmpty) {
                return IconButton(
                  icon: const Icon(
                    Icons.qr_code_2_rounded,
                    color: AppColors.pink,
                    size: 20,
                  ),
                  tooltip: SearchStrings.scanNidTooltip,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  onPressed: () async {
                    final result = await showSearchScannerSheet(context);
                    if (result != null && mounted) {
                      _ctrl.text = result;
                      widget.onChanged(result);
                    }
                  },
                );
              }
              return IconButton(
                icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textDisabled),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: () {
                  _ctrl.clear();
                  widget.onChanged('');
                },
              );
            },
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
