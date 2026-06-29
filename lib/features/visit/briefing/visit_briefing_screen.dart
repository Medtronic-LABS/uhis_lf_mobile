import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/models/programme.dart';
import '../../patient/followup_repository.dart';
import '../../patient/vitals_repository.dart';
import 'briefing_models.dart';
import 'visit_briefing_repository.dart';

/// Three-card pre-visit AI briefing screen shown after creating an encounter
/// and before triage begins.
class VisitBriefingScreen extends StatefulWidget {
  const VisitBriefingScreen({
    super.key,
    required this.encounterId,
    required this.patientId,
    this.patientName,
    this.patientAge,
    this.patientGender,
    this.householdId,
    this.memberId,
    this.programmes = const {},
    this.origin,
  });

  final String encounterId;
  final String patientId;
  final String? patientName;
  final int? patientAge;
  final String? patientGender;
  final String? householdId;
  final String? memberId;
  final Set<Programme> programmes;
  final String? origin;

  @override
  State<VisitBriefingScreen> createState() => _VisitBriefingScreenState();
}

class _VisitBriefingScreenState extends State<VisitBriefingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  Future<VisitBriefingResponse?>? _briefingFuture;

  @override
  void initState() {
    super.initState();
    _briefingFuture = _fetchBriefing();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<VisitBriefingResponse?> _fetchBriefing() async {
    try {
      final vitalsRepo = context.read<VitalsRepository>();
      final followUpRepo = context.read<FollowUpRepository>();
      final briefingRepo = context.read<VisitBriefingRepository>();

      // Gather context from local cache
      final visitsByVisit =
          await vitalsRepo.recentByVisit(widget.patientId, limit: 5);
      final followUps =
          await followUpRepo.openForPatientLocal(widget.patientId);

      // Build vitals snapshot from the most recent visit
      Map<String, dynamic>? vitalsMap;
      if (visitsByVisit.isNotEmpty) {
        final latest = visitsByVisit.first;
        final bp = latest.readings
            .where((r) => r.type == VitalType.bloodPressure)
            .firstOrNull;
        final weight = latest.readings
            .where((r) => r.type == VitalType.weight)
            .firstOrNull;
        final temp = latest.readings
            .where((r) => r.type == VitalType.temperature)
            .firstOrNull;
        final glucose = latest.readings
            .where((r) => r.type == VitalType.glucose)
            .firstOrNull;
        final spo2 =
            latest.readings.where((r) => r.type == VitalType.spO2).firstOrNull;
        final bmi =
            latest.readings.where((r) => r.type == VitalType.bmi).firstOrNull;
        vitalsMap = {
          if (bp?.systolic != null) 'bloodPressureSystolic': bp!.systolic!.toInt(),
          if (bp?.diastolic != null) 'bloodPressureDiastolic': bp!.diastolic!.toInt(),
          if (weight?.value != null) 'weight': weight!.value,
          if (temp?.value != null) 'temperature': temp!.value,
          if (glucose?.value != null) 'glucose': glucose!.value,
          if (spo2?.value != null) 'spO2': spo2!.value!.toInt(),
          if (bmi?.value != null) 'bmi': bmi!.value,
        };
      }

      // Build follow-up summaries
      final followUpSummaries = followUps.map((f) {
        final daysOverdue = f.isOverdue
            ? DateTime.now().difference(f.dueDate).inDays
            : null;
        return {
          'type': f.type.name,
          'daysOverdue': daysOverdue,
          'reason': f.reason,
        };
      }).toList();

      // Determine risk indicators
      final risks = <String>[];
      if (followUps.any((f) => f.isOverdue)) risks.add('missed_followup');
      final latestBp = visitsByVisit.isNotEmpty
          ? visitsByVisit.first.readings
              .where((r) => r.type == VitalType.bloodPressure)
              .firstOrNull
          : null;
      if (latestBp?.systolic != null && latestBp!.systolic! >= 140) {
        risks.add('elevated_bp');
      }
      if (visitsByVisit.length >= 3) risks.add('returning_patient');

      final lastVisit = visitsByVisit.isNotEmpty ? visitsByVisit.first : null;

      final request = <String, dynamic>{
        'patientId': widget.patientId,
        if (widget.patientName != null) 'patientName': widget.patientName,
        if (widget.patientAge != null) 'ageYears': widget.patientAge,
        if (widget.patientGender != null) 'gender': widget.patientGender,
        'activeProgrammes':
            widget.programmes.map((p) => p.name).toList(),
        'visitCount': visitsByVisit.length,
        if (lastVisit != null)
          'lastVisitDate': lastVisit.date.toIso8601String().split('T').first,
        if (lastVisit != null)
          'lastVisitProgramme': lastVisit.programme,
        if (vitalsMap != null && vitalsMap.isNotEmpty) 'recentVitals': vitalsMap,
        'openFollowUps': followUpSummaries,
        'riskIndicators': risks,
      };

      return await briefingRepo.generate(request);
    } on Object {
      return null;
    }
  }

  void _navigateToTriage() {
    final originParam =
        widget.origin != null ? '?origin=${widget.origin}' : '';
    context.go(
      '/patients/visit/${widget.encounterId}/triage$originParam',
      extra: {
        'patientId': widget.patientId,
        'memberId': widget.memberId,
        'householdId': widget.householdId,
        'patientAge': widget.patientAge,
      },
    );
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == 2;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.patientName ?? 'Pre-Visit Briefing'),
        centerTitle: false,
      ),
      body: FutureBuilder<VisitBriefingResponse?>(
        future: _briefingFuture,
        builder: (context, snap) {
          return Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    _BeforeYouKnockCard(
                      snap: snap,
                      patientName: widget.patientName,
                    ),
                    _ConversationGuideCard(snap: snap),
                    _TransitionCard(snap: snap),
                  ],
                ),
              ),
              _BottomBar(
                currentPage: _currentPage,
                isLastPage: isLastPage,
                onNext: _nextPage,
                onBeginAssessment: _navigateToTriage,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Card 1: Before You Knock ─────────────────────────────────────────────────

class _BeforeYouKnockCard extends StatelessWidget {
  const _BeforeYouKnockCard({required this.snap, this.patientName});

  final AsyncSnapshot<VisitBriefingResponse?> snap;
  final String? patientName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.psychology_outlined,
            iconColor: theme.colorScheme.primary,
            title: 'Before You Knock',
            subtitle:
                'AI-generated briefing based on patient history',
          ),
          const SizedBox(height: 16),
          if (snap.connectionState == ConnectionState.waiting)
            const _LoadingSkeleton(lines: 4)
          else if (snap.data == null)
            _ErrorFallback(
              message:
                  'AI briefing unavailable — check patient record manually.',
            )
          else ...[
            _HeadlineBanner(text: snap.data!.briefingCard.headline),
            const SizedBox(height: 12),
            ...snap.data!.briefingCard.points.map(
              (point) => _BulletPoint(text: point),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Card 2: Conversation Guide ────────────────────────────────────────────────

class _ConversationGuideCard extends StatelessWidget {
  const _ConversationGuideCard({required this.snap});

  final AsyncSnapshot<VisitBriefingResponse?> snap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.chat_bubble_outline,
            iconColor: Colors.teal,
            title: 'Conversation Guide',
            subtitle: 'Personalised for this patient\'s programmes and history',
          ),
          const SizedBox(height: 16),
          if (snap.connectionState == ConnectionState.waiting)
            const _LoadingSkeleton(lines: 6)
          else if (snap.data == null)
            _ErrorFallback(
              message: 'Conversation guide unavailable.',
            )
          else ...[
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.waving_hand,
                        size: 18,
                        color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        snap.data!.conversationGuide.openingLine,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...snap.data!.conversationGuide.sections
                .map((s) => _ConversationSectionTile(section: s)),
          ],
        ],
      ),
    );
  }
}

class _ConversationSectionTile extends StatefulWidget {
  const _ConversationSectionTile({required this.section});
  final ConversationSection section;

  @override
  State<_ConversationSectionTile> createState() =>
      _ConversationSectionTileState();
}

class _ConversationSectionTileState extends State<_ConversationSectionTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _iconFor(widget.section.icon);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            leading: Icon(icon, color: theme.colorScheme.primary, size: 20),
            title: Text(
              widget.section.topic,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            trailing: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 20),
            onTap: () => setState(() => _expanded = !_expanded),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.section.questions
                    .map((q) => _BulletPoint(text: q, bulletColor: Colors.teal))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(String icon) {
    switch (icon) {
      case 'heart':
        return Icons.favorite_outline;
      case 'baby':
        return Icons.child_care;
      case 'nutrition':
        return Icons.restaurant;
      case 'medication':
        return Icons.medication_outlined;
      case 'lungs':
        return Icons.air;
      case 'home':
        return Icons.home_outlined;
      default:
        return Icons.checklist_outlined;
    }
  }
}

// ── Card 3: Transition ────────────────────────────────────────────────────────

class _TransitionCard extends StatelessWidget {
  const _TransitionCard({required this.snap});
  final AsyncSnapshot<VisitBriefingResponse?> snap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = snap.data?.transitionPrompt ??
        'Ask the patient how she is feeling today and begin the consultation.';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.mic_none,
            iconColor: Colors.deepPurple,
            title: 'Begin the Consultation',
            subtitle:
                'Ask the patient how they are feeling — the AI Scribe will start listening',
          ),
          const SizedBox(height: 24),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline,
                      color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      prompt,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _FeatureBadge(
            icon: Icons.mic,
            label: 'Ambient AI Scribe',
            description:
                'Automatically transcribes and structures clinical information as you speak.',
          ),
          const SizedBox(height: 12),
          _FeatureBadge(
            icon: Icons.assignment_outlined,
            label: 'Auto-fill Assessment',
            description:
                'Relevant fields in the assessment form are populated from the conversation.',
          ),
          const SizedBox(height: 12),
          _FeatureBadge(
            icon: Icons.verified_outlined,
            label: 'You Review Everything',
            description:
                'All AI suggestions are proposals — you accept or edit before submitting.',
          ),
        ],
      ),
    );
  }
}

// ── Bottom navigation bar ──────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.currentPage,
    required this.isLastPage,
    required this.onNext,
    required this.onBeginAssessment,
  });

  final int currentPage;
  final bool isLastPage;
  final VoidCallback onNext;
  final VoidCallback onBeginAssessment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border:
            Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dot indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  3,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == currentPage ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == currentPage
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: isLastPage
                    ? FilledButton.icon(
                        onPressed: onBeginAssessment,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Begin Assessment'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      )
                    : FilledButton(
                        onPressed: onNext,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Next'),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                      ),
              ),
              if (isLastPage) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onBeginAssessment,
                  child: const Text('Skip briefing'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ─────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeadlineBanner extends StatelessWidget {
  const _HeadlineBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  const _BulletPoint({required this.text, this.bulletColor});
  final String text;
  final Color? bulletColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = bulletColor ?? theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({
    required this.icon,
    required this.label,
    required this.description,
  });

  final IconData icon;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.deepPurple),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton({required this.lines});
  final int lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        lines,
        (i) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 14,
          width: i % 3 == 2 ? 180 : double.infinity,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}

class _ErrorFallback extends StatelessWidget {
  const _ErrorFallback({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                color: theme.colorScheme.onErrorContainer, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
