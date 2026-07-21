/// AI Assistant tab — Tab 3 of the main shell.
///
/// Two sub-tabs:
///   1. "Ask AI"  — conversational Q&A backed by [AssistantRepository].
///   2. "Training" — micro-coaching modules (Learn → Apply → Measure loop).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/constants/app_strings.dart';
import '../../core/db/app_database.dart';
import '../../core/debug/console_log.dart';
import '../../core/theme/app_theme.dart';
import '../training/coaching_dao.dart';
import '../training/coaching_repository.dart';
import '../training/training_screen.dart';
import 'assistant_models.dart';
import 'assistant_repository.dart';

String _formatTime(DateTime ts) =>
    '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

// SDK-matched SpiceBlue for AI Coach branding
const _kSpiceBlue = Color(0xFF2514BE);
const _kUserBubbleBlue = Color(0xFF1565C0);

class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _kSpiceBlue,
          foregroundColor: Colors.white,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AssistantStrings.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('Online', style: TextStyle(fontSize: 11, color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ],
          ),
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            indicatorWeight: 2.5,
            labelStyle: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(icon: Icon(Icons.chat_outlined, size: 18), text: AssistantStrings.tabAsk),
              Tab(icon: Icon(Icons.school_outlined, size: 18), text: AssistantStrings.tabTraining),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ChatTab(),
            TrainingBody(),
          ],
        ),
      ),
    );
  }
}

// ── Chat tab ──────────────────────────────────────────────────────────────────

class _ChatTab extends StatefulWidget {
  const _ChatTab();

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  bool _isRecording = false;
  String? _error;
  late final ChatMessageDao _dao;

  int? _streamingMsgIdx;
  int _streamLen = 0;
  Timer? _streamTimer;

  static const List<String> _fallbackStarters = [
    AssistantStrings.suggestedMuac,
    AssistantStrings.suggestedAncDanger,
    AssistantStrings.suggestedNcd,
    AssistantStrings.suggestedReferChild,
  ];

  @override
  void initState() {
    super.initState();
    _dao = ChatMessageDao(context.read<AppDatabase>());
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await _dao.recentMessages(limit: 50);
      ConsoleLog.step('[PayloadDebug] coaching-chat history: ${rows.length} rows');
      if (!mounted) return;
      final messages = <ChatMessage>[];
      for (final row in rows) {
        final role = (row['role'] as String?) == 'user'
            ? MessageRole.user
            : MessageRole.assistant;
        final rawSq = row['suggested_questions'] as String?;
        List<String> sq = const [];
        if (rawSq != null && rawSq.isNotEmpty) {
          try {
            sq = (jsonDecode(rawSq) as List<dynamic>).whereType<String>().toList();
          } catch (_) {}
        }
        messages.add(ChatMessage(
          role: role,
          text: (row['text'] as String?) ?? '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              (row['timestamp_ms'] as int?) ?? 0),
          suggestedQuestions: sq,
        ));
      }
      if (messages.isNotEmpty) {
        setState(() => _messages.addAll(messages));
        _scrollToBottom();
      }
    } catch (e) {
      ConsoleLog.warn('[PayloadDebug] coaching-chat history load failed: $e');
    }
  }

  @override
  void dispose() {
    debugPrint('[_ChatTabState] dispose');
    _streamTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _startStreaming(int idx, String text) {
    _streamTimer?.cancel();
    setState(() {
      _streamingMsgIdx = idx;
      _streamLen = 0;
    });
    _streamTimer = Timer.periodic(const Duration(milliseconds: 12), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final next = (_streamLen + 4).clamp(0, text.length);
      setState(() => _streamLen = next);
      if (next >= text.length) {
        t.cancel();
        setState(() => _streamingMsgIdx = null);
      } else {
        _scrollToBottom();
      }
    });
  }

  Future<void> _send(String question) async {
    final q = question.trim();
    if (q.isEmpty || _loading) return;
    _input.clear();
    final now = DateTime.now();
    final userMsg = ChatMessage(role: MessageRole.user, text: q, timestamp: now);
    setState(() {
      _error = null;
      _messages.add(userMsg);
      _loading = true;
    });
    _scrollToBottom();

    try {
      await _dao.insertMessage(
        id: '${now.millisecondsSinceEpoch}_u',
        role: 'user',
        text: q,
        timestampMs: now.millisecondsSinceEpoch,
      );
    } catch (e) {
      ConsoleLog.warn('[PayloadDebug] coaching-chat persist user msg failed: $e');
    }

    final repo = context.read<AssistantRepository>();
    try {
      final answer = await repo.ask(q);
      if (!mounted) return;
      final replyTs = DateTime.now();
      final assistantMsg = ChatMessage(
        role: MessageRole.assistant,
        text: answer.text,
        timestamp: replyTs,
        actions: answer.actions,
        suggestedQuestions: answer.suggestedQuestions,
      );
      setState(() {
        _messages.add(assistantMsg);
        _loading = false;
      });
      _startStreaming(_messages.length - 1, assistantMsg.text);

      try {
        final sqJson = answer.suggestedQuestions.isEmpty
            ? null
            : jsonEncode(answer.suggestedQuestions);
        await _dao.insertMessage(
          id: '${replyTs.millisecondsSinceEpoch}_a',
          role: 'assistant',
          text: answer.text,
          timestampMs: replyTs.millisecondsSinceEpoch,
          suggestedQuestionsJson: sqJson,
        );
      } catch (e) {
        ConsoleLog.warn('[PayloadDebug] coaching-chat persist reply failed: $e');
      }
    } on AssistantException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } on Object catch (e) {
      ConsoleLog.warn('[PayloadDebug] coaching-chat unexpected error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AssistantStrings.errorMessage;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<String> _activeSuggestions(List<String> cachedFaqs) {
    if (_loading) return const [];
    if (_messages.isEmpty) {
      return cachedFaqs.isNotEmpty ? cachedFaqs.take(4).toList() : _fallbackStarters;
    }
    try {
      final last = _messages.lastWhere(
        (m) => m.role == MessageRole.assistant && m.suggestedQuestions.isNotEmpty,
      );
      return last.suggestedQuestions;
    } catch (_) {
      return const [];
    }
  }

  List<Widget> _buildMessageItems() {
    final items = <Widget>[const _TodayPill()];

    if (_messages.isEmpty) {
      items.add(const _AssistantBubble(
        text: AssistantStrings.welcomeMessage,
        timestamp: null,
      ));
    } else {
      for (var i = 0; i < _messages.length; i++) {
        final msg = _messages[i];
        final isStreaming = i == _streamingMsgIdx;
        if (msg.role == MessageRole.user) {
          items.add(_UserBubble(text: msg.text, timestamp: msg.timestamp));
        } else {
          final displayText = isStreaming
              ? '${msg.text.substring(0, _streamLen.clamp(0, msg.text.length))}▊'
              : msg.text;
          items.add(_AssistantBubble(
            text: displayText,
            timestamp: isStreaming ? null : msg.timestamp,
          ));
        }
      }
    }

    if (_loading) items.add(const _StreamingBubble(text: ''));
    items.add(const SizedBox(height: 8));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final cachedFaqs = context.watch<CoachingRepository>().cachedFaqs;
    final suggestions = _activeSuggestions(cachedFaqs);

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: _buildMessageItems(),
          ),
        ),
        if (_error != null)
          _ErrorBanner(
            message: _error!,
            onRetry: () {
              final last = _messages.lastWhere(
                (m) => m.role == MessageRole.user,
                orElse: () => ChatMessage(
                  role: MessageRole.user,
                  text: '',
                  timestamp: DateTime.now(),
                ),
              );
              if (last.text.isNotEmpty) {
                setState(() {
                  _error = null;
                  _messages.removeLast();
                });
                _send(last.text);
              } else {
                setState(() => _error = null);
              }
            },
          ),
        if (!_loading && suggestions.isNotEmpty)
          _SuggestionChipRow(chips: suggestions, onChipTap: _send),
        if (_isRecording) const _RecordingBadge(),
        const Divider(height: 1, thickness: 0.5),
        _ChatInputBar(
          controller: _input,
          loading: _loading,
          onSend: () => _send(_input.text),
          onRecordingChanged: (v) => setState(() => _isRecording = v),
        ),
      ],
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: _kSpiceBlue,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white),
    );
  }
}

// ── Today pill ────────────────────────────────────────────────────────────────

class _TodayPill extends StatelessWidget {
  const _TodayPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Chip(
          label: Text(
            AssistantStrings.todayLabel,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(50)),
          ),
          side: BorderSide.none,
        ),
      ),
    );
  }
}

// ── Assistant bubble ──────────────────────────────────────────────────────────

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text, required this.timestamp});

  final String text;
  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const _Avatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: lc.cardSurface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(color: lc.borderDefault),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(13),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (timestamp != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      _formatTime(timestamp!),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  _MessageActions(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── User bubble ───────────────────────────────────────────────────────────────

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text, required this.timestamp});

  final String text;
  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _kUserBubbleBlue,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(26),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    text,
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4),
                  child: Text(
                    _formatTime(timestamp),
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
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

// ── Streaming bubble ──────────────────────────────────────────────────────────

class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const _Avatar(),
          const SizedBox(width: 8),
          Container(
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: lc.cardSurface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: lc.borderDefault),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(13),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: text.isEmpty
                ? const _TypingDots()
                : Text(
                    '$text▊',
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Typing dots ───────────────────────────────────────────────────────────────

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final phase = _ctrl.value * 3;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? 4.0 : 0),
              child: Opacity(
                opacity: phase.toInt() == i ? 1.0 : 0.25,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Message action row (volume + thumbs) ─────────────────────────────────────

class _MessageActions extends StatelessWidget {
  const _MessageActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionIcon(icon: Icons.volume_up_rounded, onTap: () {}),
        const SizedBox(width: 4),
        _ActionIcon(icon: Icons.thumb_up_alt_outlined, onTap: () {}),
        const SizedBox(width: 4),
        _ActionIcon(icon: Icons.thumb_down_alt_outlined, onTap: () {}),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, size: 16, color: AppColors.textMuted),
    );
  }
}

// ── Suggestion chip row ───────────────────────────────────────────────────────

class _SuggestionChipRow extends StatelessWidget {
  const _SuggestionChipRow({required this.chips, required this.onChipTap});

  final List<String> chips;
  final void Function(String) onChipTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => onChipTap(chips[i]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: AppColors.navy.withAlpha(102)),
            ),
            child: Text(
              chips[i],
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.navy,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Recording badge ───────────────────────────────────────────────────────────

class _RecordingBadge extends StatefulWidget {
  const _RecordingBadge();

  @override
  State<_RecordingBadge> createState() => _RecordingBadgeState();
}

class _RecordingBadgeState extends State<_RecordingBadge>
    with TickerProviderStateMixin {
  late AnimationController _dotCtrl;
  late AnimationController _waveCtrl;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    _waveCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _dotCtrl,
                builder: (_, __) => Opacity(
                  opacity: 0.3 + 0.7 * _dotCtrl.value,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedBuilder(
                animation: _waveCtrl,
                builder: (_, __) => Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(4, (i) {
                    final phase = (_waveCtrl.value + i * 0.238) % 1.0;
                    final height = 4.0 + 10.0 * phase;
                    return Container(
                      width: 3,
                      height: height,
                      margin: EdgeInsets.only(right: i < 3 ? 2.0 : 0),
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                AssistantStrings.voiceListening,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Chat input bar ────────────────────────────────────────────────────────────

class _ChatInputBar extends StatefulWidget {
  const _ChatInputBar({
    required this.controller,
    required this.loading,
    required this.onSend,
    required this.onRecordingChanged,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSend;
  final void Function(bool) onRecordingChanged;

  @override
  State<_ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<_ChatInputBar> {
  final SpeechToText _speech = SpeechToText();
  bool _speechAvail = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _speech
        .initialize(
          onStatus: _onStatus,
          onError: (_) {
            if (mounted) _setListening(false);
          },
        )
        .then((ok) {
      if (mounted) setState(() => _speechAvail = ok);
    });
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() => setState(() {});

  void _onStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      _setListening(false);
    }
  }

  void _setListening(bool value) {
    if (!mounted) return;
    setState(() => _listening = value);
    widget.onRecordingChanged(value);
  }

  @override
  void dispose() {
    _speech.stop();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _startListening() {
    if (!_speechAvail || _listening) return;
    _speech.listen(
      onResult: (r) {
        final words = r.recognizedWords;
        widget.controller.text = words;
        widget.controller.selection =
            TextSelection.fromPosition(TextPosition(offset: words.length));
        if (r.finalResult) _setListening(false);
      },
      pauseFor: const Duration(seconds: 3),
    );
    _setListening(true);
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    _setListening(false);
  }

  @override
  Widget build(BuildContext context) {
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    final textEmpty = widget.controller.text.isEmpty;
    final sendEnabled = !textEmpty && !widget.loading;
    final borderColor = _listening ? Colors.red : lc.borderDefault;

    return Container(
      color: lc.cardSurface,
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 4,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                readOnly: _listening,
                enabled: !widget.loading,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: _listening
                      ? AssistantStrings.voiceListening
                      : AssistantStrings.inputHint,
                  hintStyle:
                      const TextStyle(color: AppColors.textMuted, fontSize: 14),
                  filled: true,
                  fillColor: lc.canvas,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(40),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(40),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(40),
                    borderSide: BorderSide(
                      color: _listening ? Colors.red : AppColors.navy,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => widget.onSend(),
              ),
            ),
            const SizedBox(width: 8),
            // Mic — always visible when STT available
            if (_speechAvail)
              GestureDetector(
                onTap: _listening ? _stopListening : _startListening,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _listening ? Colors.red : AppColors.navy,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            // Send
            GestureDetector(
              onTap: sendEnabled ? widget.onSend : null,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: sendEnabled
                      ? AppColors.navy
                      : AppColors.textMuted.withAlpha(38),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send_rounded,
                  color: sendEnabled ? Colors.white : AppColors.textMuted,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      color: lc.statusCriticalSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppColors.slaOverdueText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.slaOverdueText,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              AssistantStrings.retryLabel,
              style: const TextStyle(
                color: AppColors.slaOverdueText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
