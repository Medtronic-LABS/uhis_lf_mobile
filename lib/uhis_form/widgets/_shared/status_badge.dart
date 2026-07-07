import 'package:flutter/material.dart';

/// Compact inline status badge — Nunito 10px w800, rounded 20.
///
/// Matches the HTML `.status-badge` style exactly:
///   font: Nunito 10px w800
///   padding: 3px vertical, 8px horizontal
///   border-radius: 20px
class SdkStatusBadge extends StatelessWidget {
  const SdkStatusBadge({
    super.key,
    required this.label,
    required this.textColor,
    required this.surfaceColor,
  });

  final String label;
  final Color textColor;
  final Color surfaceColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: textColor,
          height: 1.2,
        ),
      ),
    );
  }
}
