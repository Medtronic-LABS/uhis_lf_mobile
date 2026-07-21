/// AI Assistant tab — Tab 3 of the main shell.
///
/// Two sub-tabs:
///   1. "Ask AI"  — conversational Q&A backed by [AssistantRepository].
///   2. "Training" — micro-coaching modules (Learn → Apply → Measure loop).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/db/app_database.dart';
import '../../core/debug/console_log.dart';
import '../../core/theme/app_theme.dart';
import '../training/coaching_dao.dart';
import '../training/coaching_repository.dart';
import '../training/training_screen.dart';
import 'assistant_models.dart';
import 'assistant_repository.dart';

class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          title: Text(AssistantStrings.title),
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
  String? _error;
  late final ChatMessageDao _dao;

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
      ConsoleLog.d('[PayloadDebug] coaching-chat history: ${rows.length} rows');
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
    _input.dispose();
    _scroll.dispose();
    super.dispose();
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

    // Persist user message.
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

    try {
      final answer = await context.read<AssistantRepository>().ask(q);
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

      // Persist assistant message.
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
      ConsoleLog.error('[PayloadDebug] coaching-chat unexpected error', e);
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

  @override
  Widget build(BuildContext context) {
    final cachedFaqs = context.watch<CoachingRepository>().cachedFaqs;
    final starters = cachedFaqs.isNotEmpty
        ? cachedFaqs.take(4).toList()
        : _fallbackStarters;
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? _EmptyState(onStarter: _send, starters: starters)
              : _MessageList(
                  messages: _messages,
                  loading: _loading,
                  scroll: _scroll,
                  onSuggestedQuestion: _send,
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
        _InputBar(
          controller: _input,
          loading: _loading,
          onSend: () => _send(_input.text),
        ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStarter, required this.starters});
  final void Function(String) onStarter;
  final List<String> starters;

  @override
  Widget build(BuildContext context) {
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Text(
              AssistantStrings.badgeLabel,
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            AssistantStrings.emptyHeading,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: lc.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AssistantStrings.emptySubheading,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: starters
                .map((s) => _StarterChip(label: s, onTap: () => onStarter(s)))
                .toList(),
          ),
          const SizedBox(height: 32),
          Text(
            AssistantStrings.poweredBy,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _StarterChip extends StatelessWidget {
  const _StarterChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    return ActionChip(
      label: Text(label),
      labelStyle: const TextStyle(
        fontSize: 13,
        color: AppColors.navy,
        fontWeight: FontWeight.w500,
      ),
      backgroundColor: lc.cardSurface,
      side: BorderSide(color: lc.borderDefault),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: onTap,
    );
  }
}

// ── Message list ──────────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.loading,
    required this.scroll,
    required this.onSuggestedQuestion,
  });

  final List<ChatMessage> messages;
  final bool loading;
  final ScrollController scroll;
  final void Function(String) onSuggestedQuestion;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: messages.length + (loading ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == messages.length) return const _TypingIndicator();
        return _MessageBubble(
          message: messages[i],
          onSuggestedQuestion: onSuggestedQuestion,
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onSuggestedQuestion,
  });
  final ChatMessage message;
  final void Function(String) onSuggestedQuestion;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.aiPurple,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    AssistantStrings.badgeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser ? AppColors.navy : lc.cardSurface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: isUser ? null : Border.all(color: lc.borderDefault),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : lc.textPrimary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              if (isUser) const SizedBox(width: 8),
            ],
          ),
          // Suggested follow-up questions (coaching RAG only, assistant messages).
          if (!isUser && message.suggestedQuestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AssistantStrings.suggestedFollowUps,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: message.suggestedQuestions
                        .map((q) => _StarterChip(
                              label: q,
                              onTap: () => onSuggestedQuestion(q),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    debugPrint('[_TypingIndicatorState] initState');
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    debugPrint('[_TypingIndicatorState] dispose');
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.aiPurple,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              AssistantStrings.badgeLabel,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: lc.cardSurface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: lc.borderDefault),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i / 3;
                    final t = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
                    final opacity = t < 0.5
                        ? (t * 2).clamp(0.3, 1.0)
                        : ((1 - t) * 2 + 0.3).clamp(0.3, 1.0);
                    return Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 4.0 : 0),
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: AppColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.loading,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      color: lc.cardSurface,
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !loading,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: AssistantStrings.inputHint,
                  hintStyle:
                      const TextStyle(color: AppColors.textMuted, fontSize: 14),
                  filled: true,
                  fillColor: lc.canvas,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: lc.borderDefault),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: lc.borderDefault),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: AppColors.navy),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: loading
                  ? const SizedBox(
                      width: 44,
                      height: 44,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.send_rounded),
                      color: AppColors.navy,
                      onPressed: onSend,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                        fixedSize: const Size(44, 44),
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
              style: TextStyle(
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
