import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';

class UrgentBanner extends StatelessWidget {
  const UrgentBanner({super.key, required this.patientName});

  final String patientName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.priority_high_rounded, color: scheme.error, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              WorklistStrings.urgentBannerFmt(patientName),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
