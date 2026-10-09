import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/service_member_dao.dart';
import '../../core/i18n/app_date_format.dart';
import 'enrollment/enrollment_dob.dart';

/// Flat member row — Spice [ServiceMembersAdapter] / `members_summary_list_item`.
class ServiceMemberListTile extends StatelessWidget {
  const ServiceMemberListTile({
    super.key,
    required this.row,
    required this.onTap,
  });

  final ServiceMemberListRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = row.member;
    final ageLabel = EnrollmentAge.compactChipLabel(m.dob);
    final genderInitial = (m.gender != null && m.gender!.isNotEmpty)
        ? m.gender![0].toUpperCase()
        : null;
    final ageGender = [
      if (ageLabel != null) ageLabel,
      if (genderInitial != null) genderInitial,
    ].join('/');

    final serviceKind = row.recentServiceKind?.trim();
    final serviceLabel = serviceKind != null && serviceKind.isNotEmpty
        ? ProgrammeLabels.forServiceKind(serviceKind)
        : ServiceMemberFilterStrings.recentServiceEmpty;

    final dateLabel = row.recentServiceDateMs != null
        ? AppDateFormat.dayMonthYearFmt.format(
            DateTime.fromMillisecondsSinceEpoch(row.recentServiceDateMs!),
          )
        : ServiceMemberFilterStrings.recentServiceEmpty;

    final ssLabel = _ssDisplay(m);

    return Material(
      color: m.isActive ? Colors.white : AppColors.progressTrack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: m.isActive ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      m.isActive
                          ? (m.name ?? HouseholdListStrings.unnamedMember)
                          : '${m.name ?? HouseholdListStrings.unnamedMember} (${MemberDeceasedStrings.deceased})',
                      style: const TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (m.isActive)
                    Icon(Icons.chevron_right, color: AppColors.textMuted),
                ],
              ),
              if (ageGender.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  ageGender,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _metaLine(
                ServiceMemberFilterStrings.recentServiceLabel,
                serviceLabel,
              ),
              const SizedBox(height: 4),
              _metaLine(
                ServiceMemberFilterStrings.recentServiceDateLabel,
                dateLabel,
              ),
              const SizedBox(height: 4),
              _metaLine(ServiceMemberFilterStrings.ssNameLabel, ssLabel),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _metaLine(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static String _ssDisplay(HouseholdMemberEntity m) {
    if (m.subVillageName != null && m.subVillageName!.trim().isNotEmpty) {
      return m.subVillageName!.trim();
    }
    if (m.shasthyaShebikaId != null && m.shasthyaShebikaId!.trim().isNotEmpty) {
      return m.shasthyaShebikaId!.trim();
    }
    return ServiceMemberFilterStrings.recentServiceEmpty;
  }
}
