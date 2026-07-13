import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_strings.dart';
import '../../core/models/programme.dart';
import '../../core/theme/app_theme.dart';

/// Burgundy 3-step visit progress header shared by [VisitFlowScreen] and
/// [NewPatientVisitScreen]. Extracted so both screens render identically.
class VisitFlowHeader extends StatelessWidget {
  const VisitFlowHeader({
    super.key,
    required this.step,
    required this.onBack,
    this.patientId,
    this.patientName,
    this.ageDisplay,
    this.householdId,
    this.patientGender,
    this.primaryProgramme = Programme.unknown,
  });

  final int step;
  final VoidCallback onBack;
  final String? patientId;
  final String? patientName;
  final String? ageDisplay;
  final String? householdId;
  final String? patientGender;
  final Programme primaryProgramme;

  static const Color headerColor = Color(0xFF831843);

  String get _initials {
    final name = (patientName ?? '').trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final step2Title = (primaryProgramme == Programme.anc ||
            primaryProgramme == Programme.pnc)
        ? 'Pregnancy checks'
        : VisitFlowStrings.step2Title;
    final stepLabels = <String>[
      '1. ${VisitFlowStrings.step1Title}',
      '2. $step2Title',
      '3. ${VisitFlowStrings.step3Title}',
    ];

    final subtitleParts = <String>[
      if (ageDisplay != null) ageDisplay!,
      if (patientGender != null && patientGender!.isNotEmpty)
        patientGender!.toUpperCase().startsWith('F') ? 'Female' : 'Male',
      if (householdId != null && householdId!.isNotEmpty)
        'House #$householdId',
    ];
    final subtitle = subtitleParts.join(' · ');

    return Material(
      color: headerColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: onBack,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: patientId != null
                              ? () => context.push('/patients/$patientId')
                              : null,
                          child: Text(
                            patientName ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              decoration: patientId != null
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                              decorationColor: Colors.white,
                            ),
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: List.generate(stepLabels.length, (i) {
                      final filled = i <= step;
                      return Expanded(
                        child: Container(
                          height: 3,
                          margin: EdgeInsets.only(
                            right: i == stepLabels.length - 1 ? 0 : AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: filled
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(stepLabels.length, (i) {
                      final active = i == step;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: i == stepLabels.length - 1 ? 0 : AppSpacing.sm,
                          ),
                          child: Text(
                            stepLabels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  active ? FontWeight.w800 : FontWeight.w500,
                              color: Colors.white.withValues(
                                alpha: active ? 1.0 : 0.6,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
