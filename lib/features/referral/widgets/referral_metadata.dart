import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/referral.dart';

/// Section 3 — Referral Metadata
/// Structured metadata block showing referral date, facility, condition, etc.
class ReferralMetadata extends StatelessWidget {
  const ReferralMetadata({
    super.key,
    required this.referral,
    this.facilityName,
    this.programmeName,
    this.assignedDoctor,
  });

  final Referral referral;
  final String? facilityName;
  final String? programmeName;
  final String? assignedDoctor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final referralDate = DateTime.fromMillisecondsSinceEpoch(referral.createdAt);
    final dateStr = DateFormat('d MMM').format(referralDate);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Referred date and facility
          _MetadataRow(
            label: ReferralStrings.metaReferred,
            value: _buildReferredValue(dateStr),
          ),
          const SizedBox(height: 8),
          // Row 2: Condition/Diagnosis
          if (referral.diagnosisLabel != null &&
              referral.diagnosisLabel!.isNotEmpty)
            _MetadataRow(
              label: ReferralStrings.metaCondition,
              value: referral.diagnosisLabel!,
              isHighlighted: true,
            ),
          // Optional: Programme
          if (programmeName != null && programmeName!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _MetadataRow(
              label: ReferralStrings.metaProgramme,
              value: programmeName!,
            ),
          ],
          // Optional: Assigned doctor
          if (assignedDoctor != null && assignedDoctor!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _MetadataRow(
              label: ReferralStrings.metaAssigned,
              value: assignedDoctor!,
            ),
          ],
          // Referral ID (subtle, at bottom)
          const SizedBox(height: 8),
          _MetadataRow(
            label: ReferralStrings.metaReferralId,
            value: _truncateId(referral.id),
            isSubtle: true,
          ),
        ],
      ),
    );
  }

  String _buildReferredValue(String dateStr) {
    if (facilityName != null && facilityName!.isNotEmpty) {
      return '$dateStr · $facilityName';
    }
    return dateStr;
  }

  String _truncateId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.label,
    required this.value,
    this.isHighlighted = false,
    this.isSubtle = false,
  });

  final String label;
  final String value;
  final bool isHighlighted;
  final bool isSubtle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: isSubtle
                  ? scheme.onSurface.withValues(alpha: 0.5)
                  : scheme.onSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              color: isSubtle
                  ? scheme.onSurface.withValues(alpha: 0.5)
                  : isHighlighted
                      ? scheme.primary
                      : scheme.onSurface,
              fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
