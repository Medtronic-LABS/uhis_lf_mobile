/// Generic key-value renderer for the doctor's response (Shukhee's own
/// `appointment.clinicalData`) as synced into a patient's Teleconsult
/// History. Deliberately NOT parsed against a fixed field list -- unlike
/// the live wrap-up view's `ClinicalDataCard`, which is bound to
/// `ShukheeClinicalData`'s typed fields (chiefComplaints/diagnosis/medicine/
/// etc.) and silently drops any key it doesn't yet model. Shukhee's own
/// clinicalData shape has already grown once (their 2026-09-22 API update),
/// so a synced-in historical call renders directly off the raw JSON that
/// Frappe's `Call Logs.clinical_data` stored verbatim -- a future vendor
/// field shows up here immediately, with no app/SDK change needed.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class JsonKeyValueView extends StatelessWidget {
  const JsonKeyValueView({super.key, required this.data, this.title});

  final Map<String, dynamic> data;
  final String? title;

  static bool _isPresent(Object? value) {
    if (value == null) return false;
    if (value is String) return value.isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  static String _humanize(String key) {
    final spaced = key
        .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ');
    return spaced
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((e) => _isPresent(e.value)).toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final entry in entries) ...[
            _KeyValueRow(label: _humanize(entry.key), value: entry.value),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
        ),
        const SizedBox(height: 2),
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 13),
          child: _ValueView(value: value),
        ),
      ],
    );
  }
}

/// Renders one value at any nesting depth: primitives as text, lists of
/// primitives joined inline, and maps/lists-of-maps as an indented,
/// recursively-rendered block of further key-value rows.
class _ValueView extends StatelessWidget {
  const _ValueView({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    if (value is Map) {
      final map = value.map((k, v) => MapEntry(k.toString(), v));
      final entries = map.entries.where((e) => JsonKeyValueView._isPresent(e.value)).toList();
      return Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in entries) ...[
              _KeyValueRow(label: JsonKeyValueView._humanize(entry.key), value: entry.value),
              const SizedBox(height: 4),
            ],
          ],
        ),
      );
    }
    if (value is Iterable) {
      final items = value.toList();
      final hasComplexItems = items.any((e) => e is Map || e is Iterable);
      if (!hasComplexItems) {
        return Text(items.map((e) => e.toString()).join(', '));
      }
      return Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items) ...[
              _ValueView(value: item),
              const SizedBox(height: 4),
            ],
          ],
        ),
      );
    }
    return Text(value.toString());
  }
}
