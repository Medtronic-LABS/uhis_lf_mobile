/// Multi-select via bottom sheet — API viewType `DialogCheckbox`.
///
/// Shows a summary row of selected chips (or a "None selected" hint). Tapping
/// opens a modal bottom sheet listing all options as [CheckboxListTile]s.
/// Pressing "Done" confirms the selection and calls [onChanged] with the new
/// `List<String>`.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_theme.dart';

class DialogMultiSelectField extends StatelessWidget {
  const DialogMultiSelectField({
    super.key,
    required this.labelText,
    required this.options,
    required this.onChanged,
    this.currentValue = const [],
  });

  final String labelText;
  final List<String> options;
  final List<String> currentValue;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _openSheet(context),
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(9),
              color: AppColors.cardSurface,
            ),
            child: Row(
              children: [
                Expanded(
                  child: currentValue.isEmpty
                      ? Text(
                          ComposerStrings.noneSelected,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        )
                      : Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: currentValue
                              .map((v) => _SelectionChip(label: v))
                              .toList(),
                        ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more, color: AppColors.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    // Work on a local copy so Cancel reverts.
    var draft = List<String>.from(currentValue);
    final confirmed = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _MultiSelectSheet(
        options: options,
        initial: draft,
      ),
    );
    if (confirmed != null) {
      onChanged(confirmed);
    }
  }
}

class _MultiSelectSheet extends StatefulWidget {
  const _MultiSelectSheet({
    required this.options,
    required this.initial,
  });

  final List<String> options;
  final List<String> initial;

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ComposerStrings.nSelected(_selected.length),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  child: Text(ComposerStrings.doneLabel),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: widget.options.length,
              itemBuilder: (_, i) {
                final opt = widget.options[i];
                final checked = _selected.contains(opt);
                return CheckboxListTile(
                  title: Text(opt),
                  value: checked,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.add(opt);
                      } else {
                        _selected.remove(opt);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionChip extends StatelessWidget {
  const _SelectionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textOnNavy,
        ),
      ),
    );
  }
}
