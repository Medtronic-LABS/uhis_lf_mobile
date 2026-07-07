/// Pregnancy overview hero card — [FieldKind.pregnancyProfile].
///
/// Read-only display per spec §4.2.1. Value pre-populated by
/// [DynamicAssessmentScreen] from the caller-supplied gestationalWeeks.
/// Value shape: `{"lmp": "ISO-date", "edd": "ISO-date", "weeks": int}`.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';

class PregnancyProfileWidget extends StatelessWidget {
  const PregnancyProfileWidget({
    super.key,
    required this.schema,
    this.value,
    this.onChanged,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// `{"lmp": "2024-11-12", "edd": "2025-08-19", "weeks": 30}`
  final Map<String, dynamic>? value;

  /// Kept for API compatibility — widget is always read-only per spec §4.2.1.
  final ValueChanged<Map<String, dynamic>>? onChanged;
  final bool readOnly;

  static const _gradientStart = Color(0xFFFDF2F8);
  static const _gradientEnd   = Color(0xFFF5F3FF);
  static const _cardBorder    = Color(0xFFFBCFE8);
  static const _pinkLabel     = Color(0xFF9D174D);

  @override
  Widget build(BuildContext context) {
    final lmpRaw = value?['lmp'] as String?;
    final eddRaw = value?['edd'] as String?;

    final lmpDate = lmpRaw != null ? DateTime.tryParse(lmpRaw) : null;
    final eddDate = eddRaw != null ? DateTime.tryParse(eddRaw) : null;

    if (lmpDate == null) {
      return _NoDataChip();
    }

    final totalDays = DateTime.now().difference(lmpDate).inDays;
    final weeks = totalDays ~/ 7;
    final days  = totalDays % 7;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_gradientStart, _gradientEnd],
        ),
        border: Border.all(color: _cardBorder, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero row: icon + gestational age ─────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _IconCircle(),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ComposerStrings.gestationalAgeLabel.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: _pinkLabel,
                      letterSpacing: 0.06 * 9.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _GestationalAgeText(weeks: weeks, days: days),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── LMP + EDD pill row ────────────────────────────────────────────
          Row(
            children: [
              _DatePill(
                icon: '📅',
                label: ComposerStrings.pregnancyOverviewLmp,
                date: lmpDate,
              ),
              const SizedBox(width: 16),
              _DatePill(
                icon: '🍼',
                label: ComposerStrings.pregnancyOverviewEdd,
                date: eddDate,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text('🤰', style: TextStyle(fontSize: 19)),
    );
  }
}

class _GestationalAgeText extends StatelessWidget {
  const _GestationalAgeText({required this.weeks, required this.days});

  final int weeks;
  final int days;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$weeks',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
            height: 1,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          ComposerStrings.gestationalAgeWeeks,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
        if (days > 0) ...[
          const SizedBox(width: 6),
          Text(
            '$days',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
              height: 1,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            ComposerStrings.gestationalAgeDays,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({
    required this.icon,
    required this.label,
    required this.date,
  });

  final String icon;
  final String label;
  final DateTime? date;

  static final _fmt = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final dateStr = date != null ? _fmt.format(date!) : '—';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          dateStr,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }
}

class _NoDataChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🤰', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Text(
            ComposerStrings.pregnancyOverviewNoData,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
