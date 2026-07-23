import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../theme/app_theme.dart';

/// Pink summary card showing gestational age, LMP, and EDD.
/// Used on the patient context screen and at the top of the ANC form section.
class GestationalAgeCard extends StatelessWidget {
  const GestationalAgeCard({
    super.key,
    required this.lmpDate,
    required this.eddDate,
    this.gestationalWeeks,
    this.bottomPadding = 0,
  });

  final DateTime? lmpDate;
  final DateTime? eddDate;
  final int? gestationalWeeks;
  final double bottomPadding;

  static const _pinkAccent = Color(0xFF9D174D);
  static const _navy = Color(0xFF1B2B5E);
  static const _unitGrey = Color(0xFF6B7280);

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _fmt(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final lmpStr = lmpDate != null ? _fmt(lmpDate!) : null;
    final eddStr = eddDate != null ? _fmt(eddDate!) : null;

    int? weeks;
    int? days;
    if (lmpDate != null) {
      final total = DateTime.now().difference(lmpDate!).inDays;
      weeks = total ~/ 7;
      days = total % 7;
    } else if (gestationalWeeks != null) {
      weeks = gestationalWeeks;
      days = 0;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFDF2F8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF9A8D4)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
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
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ComposerStrings.gestationalAgeLabel.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: _pinkAccent,
                        letterSpacing: 0.6,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontFamily: AppFonts.display,
                          color: _navy,
                          height: 1,
                        ),
                        children: weeks != null
                            ? [
                                TextSpan(
                                  text: '$weeks ',
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: ComposerStrings.gestationalAgeWeeks,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _unitGrey,
                                  ),
                                ),
                                if (days != null && days > 0) ...[
                                  TextSpan(
                                    text: ' $days ',
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                      color: _navy,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ComposerStrings.gestationalAgeDays,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _unitGrey,
                                    ),
                                  ),
                                ],
                              ]
                            : [
                                TextSpan(
                                  text: '— ',
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: ComposerStrings.gestationalAgeWeeks,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _unitGrey,
                                  ),
                                ),
                              ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DateSubBox(
                    emoji: '📅',
                    label: ComposerStrings.pregnancyOverviewLmp,
                    value: lmpStr,
                    valueColor: _navy,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateSubBox(
                    emoji: '🍼',
                    label: ComposerStrings.pregnancyOverviewEdd,
                    value: eddStr,
                    valueColor: const Color(0xFFDB2777),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateSubBox extends StatelessWidget {
  const _DateSubBox({
    required this.emoji,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String emoji;
  final String label;
  final String? value;
  final Color valueColor;

  static const _pinkAccent = Color(0xFF9D174D);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: _pinkAccent,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value ?? '—',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
