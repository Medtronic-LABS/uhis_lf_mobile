/// Shared 3-step progress header for the visit flow.
///
/// Matches the HTML prototype's step bar:
///   Step 1: "How are you feeling?" → Step 2: "AI triage" → Step 3: "Detailed check"
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';

/// Which of the 3 visit steps is currently active.
enum VisitStep { symptomPicker, triageResult, detailedForm }

/// Navy/indigo app bar with a 3-segment progress bar underneath.
///
/// Used by [SymptomPickerScreen], [TriageResultScreen], and
/// [SectionedAssessmentScreen] to give the SK a clear sense of progress.
class VisitStepHeader extends StatelessWidget implements PreferredSizeWidget {
  const VisitStepHeader({
    super.key,
    required this.step,
    required this.patientLabel,
    this.onBack,
  });

  final VisitStep step;

  /// Short label shown in the header title, e.g. "Rashida, Age 7".
  final String patientLabel;

  final VoidCallback? onBack;

  static const Color _headerColor = Color(0xFF1B2B5E); // Navy

  @override
  Size get preferredSize => const Size.fromHeight(104);

  @override
  Widget build(BuildContext context) {
    final stepIndex = step.index; // 0, 1, 2

    return Material(
      color: _headerColor,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back button + title row
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  if (onBack != null)
                    IconButton(
                      tooltip: 'Go back',
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: onBack,
                    )
                  else
                    const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patientLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          TriageResultStrings.stepSubtitle(stepIndex),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _bar(stepIndex >= 0, active: stepIndex == 0),
                  const SizedBox(width: 6),
                  _bar(stepIndex >= 1, active: stepIndex == 1),
                  const SizedBox(width: 6),
                  _bar(stepIndex >= 2, active: stepIndex == 2),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // Step labels
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  _label(TriageResultStrings.step1Label, stepIndex == 0),
                  const Spacer(),
                  _label(TriageResultStrings.step2Label, stepIndex == 1),
                  const Spacer(),
                  _label(TriageResultStrings.step3Label, stepIndex == 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(bool filled, {required bool active}) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 4,
        decoration: BoxDecoration(
          color: filled
              ? Colors.white
              : Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _label(String text, bool active) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        color: active
            ? Colors.white.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.5),
        fontWeight: active ? FontWeight.w700 : FontWeight.normal,
      ),
    );
  }
}
