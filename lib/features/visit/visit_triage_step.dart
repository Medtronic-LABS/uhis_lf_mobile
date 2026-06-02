import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
import 'visit_controller.dart';
import 'visit_session.dart';

/// Visit Triage Step — bilingual symptom tiles + duration selector.
///
/// Composition mirrors the HTML mockup (`Leapfrog .html` step 1):
/// navy/blue header strip with 3-step progress bar, AI brief card,
/// "SK asks family" bilingual prompt, 2-col symptom tile grid,
/// duration selector (3 buttons), pink CTA.
class VisitTriageStep extends StatelessWidget {
  const VisitTriageStep({super.key, required this.visitId});

  final String visitId;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;

    return Consumer<VisitController>(
      builder: (context, controller, _) {
        final session = controller.session;

        if (session == null || session.id != visitId) {
          return Scaffold(
            backgroundColor: tokens.canvas,
            appBar: AppBar(title: const Text(VisitTriageStrings.triage)),
            body: const SafeArea(
              child: Center(
                child: Text(VisitTriageStrings.sessionMissing),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: tokens.canvas,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TriageHeader(
                  patientName:
                      session.patientName ?? VisitTriageStrings.patient,
                  patientAge: session.patientAge,
                  programme: session.programme.wireTag,
                  onBack: () => _confirmLeave(context, session.patientId),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
                    children: [
                      _AiBriefCard(
                        patientName: session.patientName ??
                            VisitTriageStrings.patient,
                      ),
                      const SizedBox(height: 12),
                      _SkAsksFamilyCard(),
                      const SizedBox(height: 14),
                      _SymptomTilesGrid(
                        symptoms: session.symptoms,
                        onToggle: controller.toggleSymptom,
                      ),
                      const SizedBox(height: 16),
                      _DurationSelector(
                        selected: session.duration,
                        onSelect: controller.setDuration,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: ElevatedButton.icon(
                onPressed: controller.loading
                    ? null
                    : () async {
                        final success = await controller.persistTriage();
                        if (success && context.mounted) {
                          // Preserve origin query param for return navigation
                          final origin = GoRouterState.of(context).uri.queryParameters['origin'];
                          debugPrint('[Triage] origin=$origin, navigating to vitals');
                          final originParam = origin != null ? '?origin=$origin' : '';
                          context.go('/patients/visit/$visitId/vitals$originParam');
                        }
                      },
                icon: controller.loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: const Text(VisitTriageStrings.aiCheckingCta),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmLeave(BuildContext context, String patientId) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VisitTriageStrings.leaveVisitTitle),
        content: const Text(VisitTriageStrings.leaveVisitBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(VisitTriageStrings.stay),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/patients/$patientId');
            },
            child: const Text(VisitTriageStrings.leave),
          ),
        ],
      ),
    );
  }
}

class _TriageHeader extends StatelessWidget {
  const _TriageHeader({
    required this.patientName,
    required this.patientAge,
    required this.programme,
    required this.onBack,
  });

  final String patientName;
  final int? patientAge;
  final String programme;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final subtitle = patientAge != null
        ? '$patientName, Age $patientAge'
        : patientName;

    return Container(
      color: tokens.statusInfoSurface == tokens.statusInfoSurface
          ? const Color(0xFF1E40AF)
          : tokens.statusInfo,
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onBack,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visit — $subtitle',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      VisitTriageStrings.stepOneOfThree(programme),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 3-step progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: const [
                _ProgressBar(active: true),
                SizedBox(width: 6),
                _ProgressBar(active: false),
                SizedBox(width: 6),
                _ProgressBar(active: false),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: const [
                Expanded(
                  child: Text(
                    VisitTriageStrings.stepLabel1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    VisitTriageStrings.stepLabel2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    VisitTriageStrings.stepLabel3,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _AiBriefCard extends StatefulWidget {
  const _AiBriefCard({required this.patientName});

  final String patientName;

  @override
  State<_AiBriefCard> createState() => _AiBriefCardState();
}

class _AiBriefCardState extends State<_AiBriefCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.cardSurfaceMuted,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        border: Border.all(color: tokens.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tokens.brandNavy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      size: 16, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    VisitTriageStrings.beforeYouKnock,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: tokens.brandNavy,
                    ),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: tokens.textMuted,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.statusCriticalSurface,
                borderRadius: BorderRadius.circular(LeapfrogColors.radiusSm),
                border: Border(
                  left: BorderSide(color: tokens.statusCritical, width: 3),
                ),
              ),
              child: Text(
                VisitTriageStrings.briefBody(widget.patientName),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tokens.statusCritical,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkAsksFamilyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tokens.statusInfoSurface,
            tokens.statusInfoSurface.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        border: Border.all(color: tokens.statusInfo.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            VisitTriageStrings.skAsksFamily,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: tokens.statusInfo,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            VisitTriageStrings.skAsksBangla,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: tokens.brandNavy,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            VisitTriageStrings.skAsksEnglish,
            style: TextStyle(
              fontSize: 12,
              color: tokens.statusInfo,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SymptomTilesGrid extends StatelessWidget {
  const _SymptomTilesGrid({required this.symptoms, required this.onToggle});

  final List<SymptomSelection> symptoms;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.5,
      ),
      itemCount: symptoms.length,
      itemBuilder: (context, index) {
        final s = symptoms[index];
        return _SymptomTile(
          symptom: s,
          onTap: () => onToggle(s.code),
        );
      },
    );
  }
}

class _SymptomTile extends StatelessWidget {
  const _SymptomTile({required this.symptom, required this.onTap});

  final SymptomSelection symptom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final selected = symptom.selected;
    final borderColor =
        selected ? tokens.statusCritical : tokens.divider;
    final bgColor = selected
        ? tokens.statusCriticalSurface
        : tokens.cardSurface;
    final emoji = _symptomEmoji(symptom.code);
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
            border: Border.all(
              color: borderColor,
              width: selected ? 2 : 1.5,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 6),
              Text(
                symptom.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tokens.brandNavy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _symptomEmoji(String code) {
    switch (code.toLowerCase()) {
      case 'fever':
        return '🌡️';
      case 'breathing':
      case 'fast_breathing':
        return '😮‍💨';
      case 'cough':
        return '🫁';
      case 'noeat':
      case 'not_eating':
        return '🍼';
      case 'diarrhea':
      case 'loose_motion':
        return '💧';
      case 'rash':
        return '🌶️';
      case 'vomit':
      case 'vomiting':
        return '🤢';
      case 'drowsy':
      case 'sleepy':
        return '😴';
      default:
        return '🩺';
    }
  }
}

class _DurationSelector extends StatelessWidget {
  const _DurationSelector({required this.selected, required this.onSelect});

  final SymptomDuration? selected;
  final ValueChanged<SymptomDuration> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            VisitTriageStrings.durationQuestion,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: tokens.brandNavy,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final d in SymptomDuration.values) ...[
                Expanded(
                  child: _DurationButton(
                    duration: d,
                    selected: selected == d,
                    onTap: () => onSelect(d),
                  ),
                ),
                if (d != SymptomDuration.values.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DurationButton extends StatelessWidget {
  const _DurationButton({
    required this.duration,
    required this.selected,
    required this.onTap,
  });

  final SymptomDuration duration;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final isLong = duration == SymptomDuration.fourPlusDays;
    final activeFg = isLong ? tokens.statusCritical : tokens.brandNavy;
    final activeBg = isLong
        ? tokens.statusCriticalSurface
        : tokens.aiSurfaceStart;
    final bgColor = selected ? activeBg : tokens.cardSurface;
    final fgColor = selected ? activeFg : tokens.textMuted;
    final borderColor = selected ? activeFg : tokens.divider;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
            border: Border.all(
              color: borderColor,
              width: selected ? 2 : 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Center(
            child: Text(
              duration.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: fgColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
