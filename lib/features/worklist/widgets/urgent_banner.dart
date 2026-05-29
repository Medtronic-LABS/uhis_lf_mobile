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
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error),
      ),
      child: Row(
        children: [
          Icon(Icons.priority_high_rounded, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              WorklistStrings.urgentBannerFmt(patientName),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
