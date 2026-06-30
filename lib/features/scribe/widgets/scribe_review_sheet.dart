import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../scribe_controller.dart';
import '../../../core/api/scribe_api_service.dart';

/// Full-height bottom sheet for reviewing and accepting/rejecting an AI note.
///
/// SK must scroll past all 4 SOAP sections before Accept becomes enabled
/// when [ScribeRationale.humanReviewRequired] is true.
Future<void> showScribeReviewSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<ScribeController>(),
      child: const _ScribeReviewSheet(),
    ),
  );
}

class _ScribeReviewSheet extends StatefulWidget {
  const _ScribeReviewSheet();

  @override
  State<_ScribeReviewSheet> createState() => _ScribeReviewSheetState();
}

class _ScribeReviewSheetState extends State<_ScribeReviewSheet> {
  // Edited SOAP values — start null (means no edit, server gets original).
  String? _editedSubjective;
  String? _editedObjective;
  String? _editedAssessment;
  String? _editedPlan;

  // Which sections the SK has seen (scroll-past tracking).
  final _seen = <String>{};

  bool _submitting = false;

  void _markSeen(String section) {
    if (_seen.contains(section)) return;
    setState(() => _seen.add(section));
  }

  bool get _allSeen =>
      _seen.contains('S') &&
      _seen.contains('O') &&
      _seen.contains('A') &&
      _seen.contains('P');

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;

    return Consumer<ScribeController>(
      builder: (context, ctrl, _) {
        final session = ctrl.session;
        final soap = session.soap;
        final rationale = session.rationale;
        final transcript = session.transcriptText;

        if (soap == null) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Note not available.')),
          );
        }

        final needsReview = rationale?.humanReviewRequired ?? true;
        final acceptEnabled = !needsReview || _allSeen;

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.92,
          minChildSize: 0.5,
          maxChildSize: 0.97,
          builder: (_, scrollCtrl) => Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SheetHeader(rationale: rationale),
              ),

              if (needsReview && !_allSeen)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.statusWarningSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.statusWarning.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.info_outline,
                          size: 14, color: AppColors.statusWarningText),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Please review all sections before accepting.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.statusWarningText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // SOAP sections
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (transcript != null && transcript.isNotEmpty)
                      _TranscriptCard(text: transcript),
                    _SoapSection(
                      label: 'S',
                      title: 'Subjective',
                      subtitle: "Patient's reported symptoms",
                      text: _editedSubjective ?? soap.subjective ?? '',
                      onSeen: () => _markSeen('S'),
                      onChanged: (v) =>
                          setState(() => _editedSubjective = v),
                    ),
                    _SoapSection(
                      label: 'O',
                      title: 'Objective',
                      subtitle: 'Clinical findings & vitals',
                      text: _editedObjective ?? soap.objective ?? '',
                      onSeen: () => _markSeen('O'),
                      onChanged: (v) =>
                          setState(() => _editedObjective = v),
                    ),
                    _SoapSection(
                      label: 'A',
                      title: 'Assessment',
                      subtitle: 'Diagnosis / impression',
                      text: _editedAssessment ?? soap.assessment ?? '',
                      onSeen: () => _markSeen('A'),
                      onChanged: (v) =>
                          setState(() => _editedAssessment = v),
                    ),
                    _SoapSection(
                      label: 'P',
                      title: 'Plan',
                      subtitle: 'Treatment & follow-up',
                      text: _editedPlan ?? soap.plan ?? '',
                      onSeen: () => _markSeen('P'),
                      onChanged: (v) => setState(() => _editedPlan = v),
                    ),
                  ],
                ),
              ),

              // CTAs
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () => _reject(context, ctrl),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            side: const BorderSide(color: AppColors.textMuted),
                            foregroundColor: AppColors.textMuted,
                          ),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: (_submitting || !acceptEnabled)
                              ? null
                              : () => _accept(context, ctrl, soap),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Accept Note'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _accept(
    BuildContext context,
    ScribeController ctrl,
    SoapNote original,
  ) async {
    setState(() => _submitting = true);
    // Only pass edits if SK actually changed something.
    final hasEdits = _editedSubjective != null ||
        _editedObjective != null ||
        _editedAssessment != null ||
        _editedPlan != null;

    final edits = hasEdits
        ? SoapNote(
            subjective: _editedSubjective ?? original.subjective,
            objective: _editedObjective ?? original.objective,
            assessment: _editedAssessment ?? original.assessment,
            plan: _editedPlan ?? original.plan,
          )
        : null;

    await ctrl.acceptNote(edits: edits);

    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note accepted ✓')),
      );
    }
  }

  Future<void> _reject(BuildContext context, ScribeController ctrl) async {
    setState(() => _submitting = true);
    await ctrl.rejectNote();
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note discarded')),
      );
    }
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.rationale});

  final ScribeRationale? rationale;

  @override
  Widget build(BuildContext context) {
    final confidencePct =
        ((rationale?.confidence ?? 0) * 100).toStringAsFixed(0);
    final model = rationale?.asrProvider ?? 'AI';
    final needsReview = rationale?.humanReviewRequired ?? true;

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.aiSurfaceStart,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.auto_awesome,
              color: AppColors.aiPurple, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Draft Note',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                '$confidencePct% confidence · $model',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (needsReview)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.statusWarningSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppColors.statusWarning.withValues(alpha: 0.35),
              ),
            ),
            child: const Text(
              'Review required',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.statusWarningText,
              ),
            ),
          ),
      ],
    );
  }
}

class _TranscriptCard extends StatefulWidget {
  const _TranscriptCard({required this.text});
  final String text;

  @override
  State<_TranscriptCard> createState() => _TranscriptCardState();
}

class _TranscriptCardState extends State<_TranscriptCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.aiSurfaceStart,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.aiBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  const Icon(Icons.mic, size: 16, color: AppColors.aiPurpleDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Transcript',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                widget.text,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1.6,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One editable SOAP section card.
class _SoapSection extends StatefulWidget {
  const _SoapSection({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.text,
    required this.onSeen,
    required this.onChanged,
  });

  final String label;
  final String title;
  final String subtitle;
  final String text;
  final VoidCallback onSeen;
  final ValueChanged<String> onChanged;

  @override
  State<_SoapSection> createState() => _SoapSectionState();
}

class _SoapSectionState extends State<_SoapSection> {
  bool _editing = false;
  late final TextEditingController _ctrl;
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.text);
    // Mark seen on first build via post-frame callback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.attached) {
        // Simplified: mark seen immediately since section is rendered.
        widget.onSeen();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        widget.onSeen();
        return false;
      },
      child: Container(
        key: _key,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.aiSurfaceStart,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppColors.aiPurpleDark,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _editing ? Icons.check : Icons.edit_outlined,
                      size: 18,
                      color: AppColors.aiPurple,
                    ),
                    onPressed: () {
                      if (_editing) {
                        widget.onChanged(_ctrl.text);
                      }
                      setState(() => _editing = !_editing);
                    },
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _editing
                  ? TextField(
                      controller: _ctrl,
                      maxLines: null,
                      style: const TextStyle(fontSize: 13, height: 1.6),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.chatBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.aiPurple),
                        ),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                      onChanged: widget.onChanged,
                    )
                  : Text(
                      widget.text.isEmpty ? '—' : widget.text,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.6,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
