/// Patient-scoped AI assistant — the floating "✦" sheet that answers strictly
/// about one patient and surfaces safe action buttons (Start visit, Open
/// referral, Call) wired to the *same* routines the patient screen uses.
///
/// The chat itself reuses [AssistantRepository.ask] with a `patientContext`
/// payload; the backend is instructed to answer only from that context and to
/// pick actions from a fixed allowlist ([AssistantActionType]).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_strings.dart';
import '../../core/i18n/app_locale.dart';
import '../visit/visit_start_helper.dart';
import '../../core/models/programme.dart';
import '../../core/models/referral.dart';
import '../referral/referral_repository.dart';
import '../visit/visit_controller.dart';
import 'assistant_models.dart';
import 'assistant_repository.dart';

/// Everything the patient-scoped assistant needs: identity for the action
/// routines, a one-line context chip, a 2-line clinical summary, and the
/// structured [apiContext] sent to the backend.
class PatientAiContext {
  const PatientAiContext({
    required this.patientId,
    required this.patientName,
    required this.chipLine,
    required this.summary,
    required this.apiContext,
    this.patientAge,
    this.patientGender,
    this.phone,
    this.householdId,
    this.villageId,
    this.memberId,
    this.programmes = const <Programme>[],
    this.diagnosisLabel,
  });

  final String patientId;
  final String patientName;
  final int? patientAge;
  final String? patientGender;
  final String? phone;
  final String? householdId;
  final String? villageId;
  final String? memberId;
  final List<Programme> programmes;

  /// e.g. "ANC · 28y · Band 2 · BP 148/96".
  final String chipLine;

  /// 2-line clinical summary shown at the top of the sheet.
  final String summary;

  /// Referral diagnosis label default when the SK opens a referral from here.
  final String? diagnosisLabel;

  /// Structured context sent to the backend so it can answer from the data.
  final Map<String, dynamic> apiContext;

  /// Up to 4 context-aware starter questions derived from [apiContext].
  /// Shown as chips in the intro state before the first message.
  List<String> get suggestedStarters {
    final ctx = apiContext;
    final progs = (ctx['activeProgrammes'] as List?)?.cast<String>() ?? [];
    final isPregnant = ctx['isPregnant'] == true;
    final riskReasons = (ctx['riskReasons'] as List?)?.cast<String>() ?? [];
    final followUps = (ctx['openFollowUps'] as List?) ?? [];
    final vitals = ctx['recentVitals'] as Map?;
    final visits = ctx['visitCount'] as int? ?? 0;

    final questions = <String>[];

    // Overdue follow-up — highest priority
    if (followUps.isNotEmpty) {
      questions.add(PatientAiStrings.starterFollowUpsOverdue);
    }

    // Danger signs from risk reasons
    if (riskReasons.isNotEmpty) {
      questions.add(PatientAiStrings.starterDangerSigns);
    }

    // Programme-specific visit questions
    if (progs.contains('anc') && isPregnant) {
      questions.add(PatientAiStrings.starterAncProgress);
    }
    if (progs.contains('ncd')) {
      questions.add(PatientAiStrings.starterBpDiabetes);
    }
    if (progs.contains('epi')) {
      questions.add(PatientAiStrings.starterVaccines);
    }
    if (progs.contains('tb')) {
      questions.add(PatientAiStrings.starterTb);
    }
    if (progs.contains('pnc')) {
      questions.add(PatientAiStrings.starterPnc);
    }

    // Abnormal vitals
    final sbp = vitals?['bloodPressureSystolic'] as num?;
    if (sbp != null && sbp >= 140) {
      questions.add(PatientAiStrings.starterHighBp);
    }

    // Visit history
    if (visits > 0) {
      questions.add(PatientAiStrings.starterLastVisit);
    }

    // Referral question — always useful if high risk
    if (riskReasons.length >= 3) {
      questions.add(PatientAiStrings.starterReferral);
    }

    // Fallback if nothing fired
    if (questions.isEmpty) {
      return PatientAiStrings.starters;
    }

    // Dedupe and cap at 4
    final seen = <String>{};
    return questions.where(seen.add).take(4).toList();
  }
}

class PatientAiSheet extends StatefulWidget {
  const PatientAiSheet({super.key, required this.ctx});

  final PatientAiContext ctx;

  static Future<void> show(BuildContext context, PatientAiContext ctx) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PatientAiSheet(ctx: ctx),
    );
  }

  @override
  State<PatientAiSheet> createState() => _PatientAiSheetState();
}

class _PatientAiSheetState extends State<PatientAiSheet> {
  // Bounds how many prior turns ride along with each question — enough for
  // "and what about her BP?"-style follow-ups without letting a long session
  // grow the request payload unbounded.
  static const _maxHistoryTurns = 8;

  final List<ChatMessage> _messages = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = false;
  String? _error;

  final SpeechToText _speech = SpeechToText();
  bool _speechAvail = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    final ctx = widget.ctx.apiContext;
    debugPrint(
      '[PatientAI] context loaded — '
      'patient=${ctx['patientName']} '
      'age=${ctx['ageYears']} '
      'gender=${ctx['gender']} '
      'pregnant=${ctx['isPregnant']} '
      'programmes=${ctx['activeProgrammes']} '
      'riskBand=${ctx['riskBand']} '
      'visits=${ctx['visitCount']} '
      'lastVisit=${ctx['lastVisitDate']} '
      'encounters=${(ctx['recentEncounters'] as List?)?.length ?? 0} '
      'findings=${(ctx['clinicalFindings'] as List?)?.length ?? 0} '
      'followUps=${(ctx['openFollowUps'] as List?)?.length ?? 0} '
      'vitals=${ctx['recentVitals'] != null}',
    );
    _speech
        .initialize(
          onStatus: _onSpeechStatus,
          onError: (_) {
            if (mounted) _setListening(false);
          },
        )
        .then((ok) {
      if (mounted) setState(() => _speechAvail = ok);
    });
  }

  void _onSpeechStatus(String status) {
    if (status == 'done' || status == 'notListening') _setListening(false);
  }

  void _setListening(bool value) {
    if (!mounted) return;
    setState(() => _listening = value);
  }

  void _startListening() {
    if (!_speechAvail || _listening) return;
    _speech.listen(
      onResult: (r) {
        final words = r.recognizedWords;
        _input.text = words;
        _input.selection =
            TextSelection.fromPosition(TextPosition(offset: words.length));
        if (r.finalResult) _setListening(false);
      },
      localeId: AppLocale.isBangla ? 'bn-BD' : 'en-IN',
      listenOptions: SpeechListenOptions(pauseFor: const Duration(seconds: 3)),
    );
    _setListening(true);
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    _setListening(false);
  }

  @override
  void dispose() {
    debugPrint('[_PatientAiSheetState] dispose');
    _speech.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String question) async {
    debugPrint('[_PatientAiSheetState] _send question=$question');
    final q = question.trim();
    if (q.isEmpty || _loading) return;
    // Snapshot prior turns before appending this question — the backend
    // gets what led up to this question, not the question itself twice.
    final history = _recentHistory();
    _input.clear();
    setState(() {
      _error = null;
      _messages.add(ChatMessage(
        role: MessageRole.user,
        text: q,
        timestamp: DateTime.now(),
      ));
      _loading = true;
    });
    _scrollToBottom();
    try {
      final answer = await context.read<AssistantRepository>().ask(
            q,
            patientContext: widget.ctx.apiContext,
            history: history,
          );
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          role: MessageRole.assistant,
          text: answer.text,
          timestamp: DateTime.now(),
          actions: answer.actions,
        ));
        _loading = false;
      });
      _input.clear();
    } on AssistantException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
      _input.clear();
    } on Object catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AssistantStrings.errorMessage;
      });
      _input.clear();
    }
    _scrollToBottom();
  }

  /// Last [_maxHistoryTurns] messages as `{role, text}` pairs for multi-turn
  /// continuity — without this, a follow-up like "and what about her BP?"
  /// loses all context from the answer it's referring to.
  List<Map<String, String>> _recentHistory() {
    final recent = _messages.length > _maxHistoryTurns
        ? _messages.sublist(_messages.length - _maxHistoryTurns)
        : _messages;
    return recent
        .map((m) => {'role': m.role.name, 'text': m.text})
        .toList();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  // ── Actions — reuse the exact routines the patient screen uses ─────────────

  Future<void> _runAction(AssistantActionType type) async {
    debugPrint('[_PatientAiSheetState] _runAction type=$type');
    switch (type) {
      case AssistantActionType.startVisit:
        await _startVisit();
      case AssistantActionType.openReferral:
        await _openReferral();
      case AssistantActionType.callPatient:
        await _call();
      case AssistantActionType.scheduleFollowUp:
      case AssistantActionType.none:
        break;
    }
  }

  Future<void> _startVisit() async {
    debugPrint('[_PatientAiSheetState] _startVisit patientId=${widget.ctx.patientId} patientName=${widget.ctx.patientName}');
    final c = widget.ctx;
    final controller = context.read<VisitController>();
    final programme =
        c.programmes.isNotEmpty ? c.programmes.first : Programme.unknown;
    final encounterId = await startOrResumeVisit(
      context,
      controller: controller,
      patientId: c.patientId,
      programme: programme,
      patientName: c.patientName,
      patientAge: c.patientAge,
      patientGender: c.patientGender,
      householdId: c.householdId,
    );
    if (!mounted) return;
    if (encounterId != null) {
      Navigator.of(context).pop(); // close the AI sheet before navigating
      context.go('/patients/visit/$encounterId/flow?origin=patient', extra: {
        'patientId': c.patientId,
        'patientName': c.patientName,
        'patientAge': c.patientAge,
        'patientGender': c.patientGender,
        'householdId': c.householdId,
        'villageId': c.villageId,
        'memberId': c.memberId,
      });
    } else {
      _snack(controller.error ?? PatientContextStrings.startVisitFailed);
    }
  }

  Future<void> _openReferral() async {
    debugPrint('[_PatientAiSheetState] _openReferral patientId=${widget.ctx.patientId} diagnosisLabel=${widget.ctx.diagnosisLabel}');
    final c = widget.ctx;
    try {
      await context.read<ReferralRepository>().create(
            patientId: c.patientId,
            slaTier: SlaTier.urgent,
            householdId: c.householdId,
            villageId: c.villageId,
            diagnosisLabel: c.diagnosisLabel ?? c.chipLine,
          );
      if (mounted) _snack(ReferralStrings.createSuccess);
    } catch (_) {
      if (mounted) _snack(ReferralStrings.createFailed);
    }
  }

  Future<void> _call() async {
    debugPrint('[_PatientAiSheetState] _call phone=${widget.ctx.phone}');
    final phone = widget.ctx.phone;
    if (phone == null || phone.trim().isEmpty) {
      _snack(PatientAiStrings.noPhone);
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone.trim()));
    } catch (_) {
      if (mounted) _snack(PatientAiStrings.dialFailed);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.of(context).size.height * 0.88;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: height + bottomInset,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _header(scheme),
          Expanded(
            child: _messages.isEmpty
                ? _intro(scheme)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _messages.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(AssistantStrings.thinkingIndicator,
                                style: const TextStyle(fontStyle: FontStyle.italic)),
                          ),
                        );
                      }
                      return _bubble(_messages[i], scheme);
                    },
                  ),
          ),
          if (_error != null) _errorBar(scheme),
          _inputBar(scheme, bottomInset),
        ],
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    final c = widget.ctx;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  PatientAiStrings.title(c.patientName),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _intro(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(PatientAiStrings.intro,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.ctx.suggestedStarters
              .map((s) => ActionChip(label: Text(s), onPressed: () => _send(s)))
              .toList(),
        ),
      ],
    );
  }

  Widget _bubble(ChatMessage m, ColorScheme scheme) {
    final isUser = m.role == MessageRole.user;
    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            m.text,
            style: TextStyle(
                fontSize: 14,
                color: isUser ? Colors.white : scheme.onSurface),
          ),
        ),
        if (m.actions.isNotEmpty) _actionBar(m.actions, scheme),
      ],
    );
  }

  Widget _actionBar(List<AssistantAction> actions, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: actions.map((a) {
          return FilledButton.tonalIcon(
            onPressed: () => _runAction(a.type),
            icon: Icon(_actionIcon(a.type), size: 16),
            label: Text(a.label),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _actionIcon(AssistantActionType t) {
    switch (t) {
      case AssistantActionType.startVisit:
        return Icons.play_arrow_rounded;
      case AssistantActionType.openReferral:
        return Icons.send_rounded;
      case AssistantActionType.callPatient:
        return Icons.call;
      case AssistantActionType.scheduleFollowUp:
        return Icons.event_outlined;
      case AssistantActionType.none:
        return Icons.circle;
    }
  }

  Widget _errorBar(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_error!,
                  style: TextStyle(color: scheme.onErrorContainer, fontSize: 12))),
          TextButton(
            onPressed: () {
              final last = _messages.lastWhere(
                (m) => m.role == MessageRole.user,
                orElse: () => ChatMessage(
                    role: MessageRole.user, text: '', timestamp: DateTime.now()),
              );
              if (last.text.isNotEmpty) {
                setState(() => _error = null);
                _send(last.text);
              }
            },
            child: Text(AssistantStrings.retryLabel),
          ),
        ],
      ),
    );
  }

  Widget _inputBar(ColorScheme scheme, double bottomInset) {
    final borderColor = _listening ? Colors.red : scheme.outline;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 10 + bottomInset),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  readOnly: _listening,
                  enabled: !_loading,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: _listening
                        ? AssistantStrings.voiceListening
                        : PatientAiStrings.inputHint,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: _listening ? Colors.red : scheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_speechAvail)
                GestureDetector(
                  onTap: _listening ? _stopListening : _startListening,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _listening ? Colors.red : scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              if (_speechAvail) const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _loading ? null : () => _send(_input.text),
                style: IconButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                ),
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(PatientAiStrings.scopeNote,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
