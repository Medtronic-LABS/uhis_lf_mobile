/// Assistant tab — Personalised Coaching hub (Coaching + Leaderboard tabs)
/// with floating AI Coach chat button.
/// Built fresh — no imports from training_screen.dart.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_strings.dart';
import '../../core/db/app_database.dart';
import '../../core/debug/console_log.dart';
import '../../core/theme/app_theme.dart';
import '../training/all_modules_screen.dart';
import '../training/coaching_dao.dart';
import '../training/coaching_models.dart';
import '../training/coaching_repository.dart';
import '../training/coaching_stt_service.dart';
import '../training/coaching_tts_service.dart';
import '../training/knowledge_list_screen.dart';
import '../training/module_detail_screen.dart';
import '../training/quiz_screen.dart';
import '../training/gemma_model_manager.dart';
import '../training/offline_llm_service.dart';
import '../training/stt_model_manager.dart';
import '../training/training_requests_screen.dart';
import 'assistant_models.dart';
import 'assistant_repository.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────

const _kSpiceBlue = Color(0xFF2514BE);
const _kSpiceBlueDark = Color(0xFF1A0EA0);
const _kSpiceBlueContainer = Color(0xFFE8F0FE);
const _kMetaGray = Color(0xFF6B7280);
const _kNavy = Color(0xFF1B2B5E);
const _kGold = Color(0xFFFFC107);
const _kSilver = Color(0xFFBDBDBD);
const _kBronze = Color(0xFFCD7F32);
const _kUserBlue = Color(0xFF1565C0);

String _fmt(DateTime ts) =>
    '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

// ─── AssistantScreen ──────────────────────────────────────────────────────────

class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: _kSpiceBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Personalised Coaching',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 2.5,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            unselectedLabelStyle: TextStyle(fontSize: 14),
            tabs: [
              Tab(text: 'Coaching'),
              Tab(text: 'Leaderboard'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CoachingTab(),
            _LeaderboardTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const _AiChatScreen()),
          ),
          backgroundColor: _kSpiceBlue,
          foregroundColor: Colors.white,
          child: const Icon(Icons.chat_bubble_rounded),
        ),
      ),
    );
  }
}

// ─── Coaching tab ─────────────────────────────────────────────────────────────

class _CoachingTab extends StatefulWidget {
  const _CoachingTab();

  @override
  State<_CoachingTab> createState() => _CoachingTabState();
}

class _CoachingTabState extends State<_CoachingTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CoachingRepository>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<CoachingRepository>();
    final modules = repo.modules;
    final priorities = repo.todaysPriorities;
    final gaps = repo.gapModules;
    ConsoleLog.step('[AssistantScreen] coaching modules=${modules.length} priorities=${priorities.length} gaps=${gaps.length}');

    if (repo.isSyncing && modules.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (modules.isNotEmpty) ...[
            _MorningCard(
              module: priorities.isNotEmpty ? priorities.first : modules.first,
            ),
            const SizedBox(height: 20),
          ],
          const _SectionHeader(label: 'Refreshers'),
          const SizedBox(height: 8),
          if (gaps.isEmpty)
            const _EmptyState(msg: 'No refreshers yet.')
          else
            ...gaps.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RefresherTile(module: m),
            )),
          const SizedBox(height: 20),
          _TrainingHeader(modules: modules),
          const SizedBox(height: 10),
          _TrainingScroll(modules: modules),
          const SizedBox(height: 24),
          const _KnowledgeHeader(),
          const SizedBox(height: 10),
          const _KnowledgeScroll(),
          const SizedBox(height: 20),
          const _TrainingRequestsCard(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Morning card ─────────────────────────────────────────────────────────────

class _MorningCard extends StatelessWidget {
  const _MorningCard({required this.module});

  final CoachingModule module;

  String get _questionText {
    if (module.quiz.isNotEmpty) {
      final q = module.quiz.first;
      return q.questionBn.isNotEmpty ? q.questionBn : q.questionEn;
    }
    return module.titleBn.isNotEmpty ? module.titleBn : module.titleEn;
  }

  void _onTap(BuildContext context) {
    if (module.quiz.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => QuizScreen(module: module)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ModuleDetailScreen(module: module)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) {
        final thumb = ctx.watch<CoachingRepository>().moduleThumbnailUrl(module.id);
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              if (thumb != null)
                Positioned.fill(
                  child: Image.network(
                    thumb,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _kSpiceBlue.withValues(alpha: thumb != null ? 0.82 : 1.0),
                        _kSpiceBlueDark.withValues(alpha: thumb != null ? 0.82 : 1.0),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MICRO-COACHING',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _questionText,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.4,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton(
                      onPressed: () => _onTap(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white60, width: 1.5),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      ),
                      child: const Text(
                        'Tap to answer',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Training section ─────────────────────────────────────────────────────────

class _TrainingHeader extends StatelessWidget {
  const _TrainingHeader({required this.modules});

  final List<CoachingModule> modules;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Training',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => AllModulesScreen(modules: modules)),
          ),
          child: const Text(
            'See all',
            style: TextStyle(color: _kSpiceBlue, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _TrainingScroll extends StatelessWidget {
  const _TrainingScroll({required this.modules});

  final List<CoachingModule> modules;

  @override
  Widget build(BuildContext context) {
    if (modules.isEmpty) {
      return const _EmptyState(msg: 'No modules yet.');
    }
    return SizedBox(
      height: 215,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: modules.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) => _ModuleCard(module: modules[i]),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final CoachingModule module;

  Color get _domainColor => switch (module.domain) {
    CoachingDomain.ncd       => const Color(0xFFE53935),
    CoachingDomain.anc       => const Color(0xFF8E24AA),
    CoachingDomain.imci      => const Color(0xFF00897B),
    CoachingDomain.tb        => const Color(0xFFF57C00),
    CoachingDomain.epi       => const Color(0xFF1E88E5),
    CoachingDomain.nutrition => const Color(0xFF43A047),
  };

  String get _domainLabel => switch (module.domain) {
    CoachingDomain.ncd       => 'NCD',
    CoachingDomain.anc       => 'ANC',
    CoachingDomain.imci      => 'IMCI',
    CoachingDomain.tb        => 'TB',
    CoachingDomain.epi       => 'EPI',
    CoachingDomain.nutrition => 'NUTRITION',
  };

  @override
  Widget build(BuildContext context) {
    final title = module.titleBn.isNotEmpty ? module.titleBn : module.titleEn;
    final meta = '${module.estimatedMinutes} min · ${module.quiz.length} questions';
    final done = module.isCompleted;
    final pct = done ? '100%' : '${(module.progressFraction * 100).toInt()}%';
    const kGreen = Color(0xFF2E7D32);

    return GestureDetector(
      onTap: () {
        if (module.isLocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(TrainingStrings.lockedSnackbar),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ModuleDetailScreen(module: module)),
        );
      },
      child: SizedBox(
        width: 170,
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail with badge overlays
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Stack(
                  children: [
                    Builder(
                      builder: (ctx) {
                        final thumb =
                            ctx.watch<CoachingRepository>().moduleThumbnailUrl(module.id);
                        if (thumb != null) {
                          return Image.network(
                            thumb,
                            height: 100,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 100,
                              width: double.infinity,
                              color: _kSpiceBlueContainer,
                            ),
                          );
                        }
                        return Container(height: 100, width: double.infinity, color: _kSpiceBlueContainer);
                      },
                    ),
                    // Domain badge — top-left
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: _domainColor.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _domainLabel,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    // Completed checkmark — top-right
                    if (done)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    // Lock overlay with icon
                    if (module.isLocked)
                      Container(
                        height: 100,
                        width: double.infinity,
                        color: Colors.black.withValues(alpha: 0.38),
                        child: const Center(
                          child: Icon(Icons.lock_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                    // Playing indicator — bottom-right
                    if (module.isPlaying && !module.isLocked)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: _kSpiceBlue.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              // Content below thumbnail
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _kNavy,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(meta, style: const TextStyle(fontSize: 11, color: _kMetaGray)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (done ? 1.0 : module.progressFraction).clamp(0.0, 1.0),
                      color: done ? kGreen : _kSpiceBlue,
                      backgroundColor: _kSpiceBlueContainer,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pct,
                      style: TextStyle(fontSize: 11, color: done ? kGreen : _kMetaGray),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Refresher tile ───────────────────────────────────────────────────────────

class _RefresherTile extends StatelessWidget {
  const _RefresherTile({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    final title = module.titleBn.isNotEmpty ? module.titleBn : module.titleEn;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ModuleDetailScreen(module: module)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _kSpiceBlueContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.refresh_rounded, color: _kSpiceBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${module.estimatedMinutes} min',
                      style: const TextStyle(fontSize: 12, color: _kMetaGray),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _kMetaGray),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Knowledge section ────────────────────────────────────────────────────────

class _KnowledgeHeader extends StatelessWidget {
  const _KnowledgeHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          CoachingStrings.knowledgeSection,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const KnowledgeListScreen()),
          ),
          child: Text(
            CoachingStrings.seeAll,
            style: const TextStyle(color: _kSpiceBlue, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _KnowledgeScroll extends StatelessWidget {
  const _KnowledgeScroll();

  @override
  Widget build(BuildContext context) {
    final docs = context.watch<CoachingRepository>().knowledgeDocs;
    ConsoleLog.step('[AssistantScreen] knowledge docs=${docs.length}');
    if (docs.isEmpty) return const _EmptyState(msg: 'No documents yet.');
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: docs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) => _KnowledgeCard(doc: docs[i]),
      ),
    );
  }
}

class _KnowledgeCard extends StatelessWidget {
  const _KnowledgeCard({required this.doc});

  final KnowledgeDocument doc;

  Color get _domainColor => switch (doc.domain) {
    CoachingDomain.ncd       => const Color(0xFFE53935),
    CoachingDomain.anc       => const Color(0xFF8E24AA),
    CoachingDomain.imci      => const Color(0xFF00897B),
    CoachingDomain.tb        => const Color(0xFFF57C00),
    CoachingDomain.epi       => const Color(0xFF1E88E5),
    CoachingDomain.nutrition => const Color(0xFF43A047),
  };

  String get _domainLabel => switch (doc.domain) {
    CoachingDomain.ncd       => 'NCD',
    CoachingDomain.anc       => 'ANC',
    CoachingDomain.imci      => 'IMCI',
    CoachingDomain.tb        => 'TB',
    CoachingDomain.epi       => 'EPI',
    CoachingDomain.nutrition => 'Nutrition',
  };

  Future<void> _open(BuildContext context) async {
    final url = doc.presignedUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ConsoleLog.warn('[KnowledgeCard] Could not open $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = doc.titleBn.isNotEmpty ? doc.titleBn : doc.titleEn;
    return GestureDetector(
      onTap: () => _open(context),
      child: SizedBox(
        width: 150,
        child: Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: doc.thumbnailPresignedUrl != null
                          ? Image.network(
                              doc.thumbnailPresignedUrl!,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 36,
                                height: 36,
                                color: _kSpiceBlueContainer,
                                child: const Icon(Icons.description_rounded, color: _kSpiceBlue, size: 20),
                              ),
                            )
                          : Container(
                              width: 36,
                              height: 36,
                              color: _kSpiceBlueContainer,
                              child: const Icon(Icons.description_rounded, color: _kSpiceBlue, size: 20),
                            ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: _domainColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _domainLabel,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _domainColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF101828)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kSpiceBlueContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    doc.docType,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _kSpiceBlue),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Training requests card ───────────────────────────────────────────────────

class _TrainingRequestsCard extends StatelessWidget {
  const _TrainingRequestsCard();

  @override
  Widget build(BuildContext context) {
    final pending = MockCoachingData.trainingRequests
        .where((r) => r.status == TrainingRequestStatus.pending)
        .length;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TrainingRequestsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _kSpiceBlueContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.school_rounded, color: _kSpiceBlue, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      CoachingStrings.trainingRequestsSection,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF101828)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pending > 0 ? '$pending pending' : CoachingStrings.requestTrainingCta,
                      style: const TextStyle(fontSize: 12, color: _kMetaGray),
                    ),
                  ],
                ),
              ),
              if (pending > 0)
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: _kSpiceBlue, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(
                    '$pending',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                )
              else
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF6B7280)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.msg});

  final String msg;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Center(
        child: Text(msg, style: const TextStyle(color: _kMetaGray, fontSize: 14)),
      ),
    );
  }
}

// ─── Leaderboard tab ──────────────────────────────────────────────────────────

class _LeaderboardTab extends StatefulWidget {
  const _LeaderboardTab();

  @override
  State<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<_LeaderboardTab> {
  int _filterIdx = 0;

  static const _filters = ['All Time', 'This Month', 'This Week'];

  @override
  Widget build(BuildContext context) {
    final entries = MockCoachingData.leaderboard;
    ConsoleLog.step('[AssistantScreen] leaderboard entries=${entries.length} (mock — no leaderboard API connected)');
    final top3 = entries.where((e) => e.rank <= 3).toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final rest = entries.where((e) => e.rank > 3 && !e.isCurrentUser).toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final me = entries.firstWhere(
      (e) => e.isCurrentUser,
      orElse: () => entries.last,
    );

    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: List.generate(_filters.length, (i) {
              final selected = i == _filterIdx;
              return Padding(
                padding: EdgeInsets.only(right: i < _filters.length - 1 ? 8 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _filterIdx = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? _kSpiceBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                      border: selected ? null : Border.all(color: const Color(0xFFE4E7EC)),
                    ),
                    child: Text(
                      _filters[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.black54,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        // Context row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Text('Dhamrai Upazila · 28 SKs',
                  style: const TextStyle(fontSize: 12, color: _kMetaGray)),
              const Spacer(),
              Text('Updated 12:00', style: const TextStyle(fontSize: 12, color: _kMetaGray)),
            ],
          ),
        ),

        // Podium
        if (top3.isNotEmpty) _Podium(top3: top3),

        // List
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: rest.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _LeaderRow(entry: rest[i], isYou: false),
          ),
        ),

        // Pinned You
        _YouRow(entry: me),
      ],
    );
  }
}

// ─── Podium ───────────────────────────────────────────────────────────────────

class _Podium extends StatelessWidget {
  const _Podium({required this.top3});

  final List<LeaderboardEntry> top3;

  @override
  Widget build(BuildContext context) {
    final rank1 = top3.firstWhere((e) => e.rank == 1, orElse: () => top3[0]);
    final rank2 = top3.firstWhere((e) => e.rank == 2, orElse: () => top3[0]);
    final rank3 = top3.length >= 3
        ? top3.firstWhere((e) => e.rank == 3, orElse: () => top3.last)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _PodiumCard(entry: rank2, badgeColor: _kSilver, avatarRadius: 26)),
          const SizedBox(width: 8),
          Expanded(child: _PodiumCard(entry: rank1, badgeColor: _kGold, avatarRadius: 32)),
          const SizedBox(width: 8),
          if (rank3 != null)
            Expanded(child: _PodiumCard(entry: rank3, badgeColor: _kBronze, avatarRadius: 26))
          else
            const Expanded(child: SizedBox()),
        ],
      ),
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({
    required this.entry,
    required this.badgeColor,
    required this.avatarRadius,
  });

  final LeaderboardEntry entry;
  final Color badgeColor;
  final double avatarRadius;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Color(0x12000000), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: avatarRadius,
                backgroundColor: _kSpiceBlueContainer,
                child: Text(
                  entry.initials,
                  style: TextStyle(
                    fontSize: avatarRadius * 0.45,
                    fontWeight: FontWeight.bold,
                    color: _kSpiceBlue,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                entry.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.points} XP',
                style: const TextStyle(fontSize: 11, color: _kMetaGray),
              ),
              if (entry.streakDays > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '🔥 ${entry.streakDays}d',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
        CircleAvatar(
          radius: 14,
          backgroundColor: badgeColor,
          child: Text(
            '${entry.rank}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

// ─── Leader row ───────────────────────────────────────────────────────────────

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.entry, required this.isYou});

  final LeaderboardEntry entry;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isYou ? _kNavy : Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: isYou
            ? null
            : const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${entry.rank}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isYou ? Colors.white : Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 20,
            backgroundColor: isYou ? Colors.white24 : _kSpiceBlueContainer,
            child: Text(
              entry.initials,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isYou ? Colors.white : _kSpiceBlue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isYou && entry.isCurrentUser ? 'You' : entry.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isYou ? Colors.white : Colors.black87,
                  ),
                ),
                if (entry.streakDays > 0)
                  Text(
                    '🔥 ${entry.streakDays}d',
                    style: TextStyle(
                      fontSize: 12,
                      color: isYou ? Colors.white70 : _kMetaGray,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isYou ? Colors.white24 : _kSpiceBlueContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${entry.points} XP',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isYou ? Colors.white : _kSpiceBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _YouRow extends StatelessWidget {
  const _YouRow({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 12,
        top: 8,
      ),
      child: _LeaderRow(entry: entry, isYou: true),
    );
  }
}

// ─── AI Chat screen ───────────────────────────────────────────────────────────

class _AiChatScreen extends StatelessWidget {
  const _AiChatScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // White inline header — matches spice-coaching-android SDK
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE4E7EC), width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF101828)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _kSpiceBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'AI Coach',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF101828),
                          ),
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
                            const Text(
                              'Online',
                              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF6B7280)),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF6B7280)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Expanded(child: _ChatBody()),
          ],
        ),
      ),
    );
  }
}

// ─── Chat body ────────────────────────────────────────────────────────────────

class _ChatBody extends StatefulWidget {
  const _ChatBody();

  @override
  State<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends State<_ChatBody> {
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

  final GemmaModelManager _gemmaManager = GemmaModelManager();
  final SttModelManager _sttDownloadManager = SttModelManager();
  final OfflineLlmService _offlineLlm = OfflineLlmService();

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
    _checkModels();
  }

  /// On startup: only check if models are already present (no auto-download).
  /// User must explicitly tap Download to start downloads.
  Future<void> _checkModels() async {
    await Future.wait([
      _gemmaManager.checkIfReady(),
      _sttDownloadManager.checkIfReady(),
    ]);
    final state = _gemmaManager.currentState;
    if (state is GemmaModelReady) {
      _initGemmaLlm(state.modelPath);
    }
  }

  Future<void> _initGemmaLlm(String modelPath) async {
    try {
      await _offlineLlm.initialize(modelPath);
      ConsoleLog.success('[ChatBody] Gemma on-device LLM initialized');
    } catch (e) {
      ConsoleLog.warn('[ChatBody] Gemma init failed: $e');
    }
  }

  Future<void> _startGemmaDownload() async {
    await _gemmaManager.downloadIfNeeded();
    final state = _gemmaManager.currentState;
    if (state is GemmaModelReady) {
      _initGemmaLlm(state.modelPath);
    }
  }

  Future<void> _startSttDownload() => _sttDownloadManager.downloadIfNeeded();

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
    _streamTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    _gemmaManager.dispose();
    _sttDownloadManager.dispose();
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
    final repo = context.read<AssistantRepository>();
    final coaching = context.read<CoachingRepository>();

    // Build offline RAG context from cached module lesson content.
    final contextDocs = coaching.modules.expand((m) {
      return m.cards.expand((c) {
        return c.blocks
            .where((b) => b.text != null && b.text!.isNotEmpty)
            .map((b) => '[${m.titleEn}] ${b.text!}');
      });
    }).take(30).toList();

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
      final answer = await repo.ask(q, contextDocs: contextDocs);
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

    return StreamBuilder<GemmaModelState>(
      stream: _gemmaManager.stateStream,
      initialData: _gemmaManager.currentState,
      builder: (ctx, gemmaSnap) {
        final gemmaState = gemmaSnap.data ?? _gemmaManager.currentState;
        if (gemmaState is GemmaModelReady) {
          return _buildChat(context, cachedFaqs, suggestions);
        }
        return StreamBuilder<SttModelState>(
          stream: _sttDownloadManager.stateStream,
          initialData: _sttDownloadManager.currentState,
          builder: (ctx2, sttSnap) {
            final sttState = sttSnap.data ?? _sttDownloadManager.currentState;
            return _ModelNotReadyScreen(
              gemmaState: gemmaState,
              sttState: sttState,
              onDownloadGemma: _startGemmaDownload,
              onDownloadStt: _startSttDownload,
              onDownloadBoth: () {
                _startGemmaDownload();
                _startSttDownload();
              },
              onClose: () => Navigator.of(context).maybePop(),
            );
          },
        );
      },
    );
  }

  Widget _buildChat(
      BuildContext context, List<String> cachedFaqs, List<String> suggestions) {
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

// ─── Model not ready screen ───────────────────────────────────────────────────

class _ModelNotReadyScreen extends StatelessWidget {
  const _ModelNotReadyScreen({
    required this.gemmaState,
    required this.sttState,
    required this.onDownloadGemma,
    required this.onDownloadStt,
    required this.onDownloadBoth,
    required this.onClose,
  });

  final GemmaModelState gemmaState;
  final SttModelState sttState;
  final VoidCallback onDownloadGemma;
  final VoidCallback onDownloadStt;
  final VoidCallback onDownloadBoth;
  final VoidCallback onClose;

  bool get _gemmaInFlight =>
      gemmaState is GemmaModelDownloading;
  bool get _sttInFlight =>
      sttState is SttModelStateDownloading || sttState is SttModelStateExtracting;
  bool get _gemmaIdle =>
      gemmaState is GemmaModelIdle || gemmaState is GemmaModelFailed;
  bool get _sttIdle =>
      sttState is SttModelStateIdle || sttState is SttModelStateFailed;
  bool get _showBothCta => _gemmaIdle && _sttIdle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Icon + heading ───────────────────────────────────────────────────
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _kSpiceBlue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 28, color: _kSpiceBlue),
          ),
          const SizedBox(height: 16),
          Text(
            'AI Coaching Chat',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold, color: _kSpiceBlue),
          ),
          const SizedBox(height: 8),
          Text(
            'A one-time download is needed for offline AI coaching. '
            'AI model is required; voice model is optional.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          // ── AI model card ────────────────────────────────────────────────────
          _DownloadCard(
            icon: Icons.psychology_rounded,
            title: 'AI Coaching Model',
            sizeLabel: '~304 MB  •  Required',
            isRequired: true,
            state: gemmaState,
            onDownload: onDownloadGemma,
            onCancel: () {}, // GemmaModelManager.cancel() wired via parent
          ),
          const SizedBox(height: 12),
          // ── Voice model card ─────────────────────────────────────────────────
          _DownloadCard(
            icon: Icons.mic_rounded,
            title: 'Bengali Voice Model',
            sizeLabel: '~90 MB  •  Optional',
            isRequired: false,
            state: sttState,
            onDownload: onDownloadStt,
            onCancel: () {},
          ),
          // ── Download both ────────────────────────────────────────────────────
          if (_showBothCta) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download both'),
                onPressed: onDownloadBoth,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Wi-Fi recommended. Downloads happen in background.',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          TextButton(
            onPressed: onClose,
            child: Text(
              _gemmaInFlight || _sttInFlight
                  ? 'Continue in background'
                  : 'Maybe later',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Download card ────────────────────────────────────────────────────────────

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.icon,
    required this.title,
    required this.sizeLabel,
    required this.isRequired,
    required this.state,
    required this.onDownload,
    required this.onCancel,
  });

  final IconData icon;
  final String title;
  final String sizeLabel;
  final bool isRequired;
  final dynamic state; // GemmaModelState or SttModelState
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  bool get _isReady =>
      state is GemmaModelReady || state is SttModelStateReady;

  bool get _isFailed =>
      state is GemmaModelFailed || state is SttModelStateFailed;

  bool get _isDownloading {
    if (state is GemmaModelDownloading) return true;
    if (state is SttModelStateDownloading || state is SttModelStateExtracting) {
      return true;
    }
    return false;
  }

  int? get _progress {
    if (state is GemmaModelDownloading) {
      return (state as GemmaModelDownloading).progress;
    }
    if (state is SttModelStateDownloading) {
      return (state as SttModelStateDownloading).percent;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(
          color: _isReady
              ? Colors.green.shade300
              : _isFailed
                  ? Colors.red.shade300
                  : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(12),
        color: _isReady
            ? Colors.green.shade50
            : Theme.of(context).cardColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: _kSpiceBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(sizeLabel,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              if (_isReady)
                const Icon(Icons.check_circle_rounded,
                    color: Colors.green, size: 20)
              else if (!_isDownloading)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor:
                        _isFailed ? Colors.red.shade700 : null,
                    side: _isFailed
                        ? BorderSide(color: Colors.red.shade300)
                        : null,
                  ),
                  onPressed: onDownload,
                  child: Text(
                    _isFailed ? 'Retry' : 'Download',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          if (_isFailed) ...[
            const SizedBox(height: 6),
            Text(
              state is GemmaModelFailed
                  ? (state as GemmaModelFailed).error
                  : state is SttModelStateFailed
                      ? (state as SttModelStateFailed).error
                      : 'Download failed',
              style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (_isDownloading) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: _progress != null && _progress! > 0
                        ? _progress! / 100.0
                        : null,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                if (_progress != null && _progress! > 0) ...[
                  const SizedBox(width: 8),
                  Text('$_progress%',
                      style: const TextStyle(fontSize: 11)),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              state is SttModelStateExtracting
                  ? 'Extracting…'
                  : 'Downloading…',
              style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Avatar ───────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(color: _kSpiceBlue, shape: BoxShape.circle),
      child: const Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white),
    );
  }
}

// ─── Today pill ───────────────────────────────────────────────────────────────

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

// ─── Assistant bubble ─────────────────────────────────────────────────────────

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
                      _fmt(timestamp!),
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: 2),
                  _MessageActions(text: text),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── User bubble ──────────────────────────────────────────────────────────────

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _kUserBlue,
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
                  _fmt(timestamp),
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Message actions ──────────────────────────────────────────────────────────

class _MessageActions extends StatefulWidget {
  const _MessageActions({required this.text});
  final String text;

  @override
  State<_MessageActions> createState() => _MessageActionsState();
}

class _MessageActionsState extends State<_MessageActions> {
  final CoachingTtsService _tts = CoachingTtsService();
  bool _speaking = false;

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  Future<void> _toggleSpeech() async {
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
    } else {
      if (mounted) setState(() => _speaking = true);
      await _tts.speak(widget.text);
      if (mounted) setState(() => _speaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionBtn(
          icon: _speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
          onTap: _toggleSpeech,
        ),
        const SizedBox(width: 4),
        const _ActionBtn(icon: Icons.thumb_up_alt_outlined),
        const SizedBox(width: 4),
        const _ActionBtn(icon: Icons.thumb_down_alt_outlined),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        size: 16,
        color: onTap != null ? AppColors.navy : AppColors.textMuted,
      ),
    );
  }
}

// ─── Streaming bubble ─────────────────────────────────────────────────────────

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

// ─── Typing dots ──────────────────────────────────────────────────────────────

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
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
      builder: (_, _) {
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

// ─── Suggestion chip row ──────────────────────────────────────────────────────

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
        separatorBuilder: (_, _) => const SizedBox(width: 8),
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
              style: const TextStyle(fontSize: 12, color: AppColors.navy, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Recording badge ──────────────────────────────────────────────────────────

class _RecordingBadge extends StatefulWidget {
  const _RecordingBadge();

  @override
  State<_RecordingBadge> createState() => _RecordingBadgeState();
}

class _RecordingBadgeState extends State<_RecordingBadge> with TickerProviderStateMixin {
  late AnimationController _dotCtrl;
  late AnimationController _waveCtrl;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _waveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
      ..repeat(reverse: true);
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
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(50)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _dotCtrl,
                builder: (_, _) => Opacity(
                  opacity: 0.3 + 0.7 * _dotCtrl.value,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedBuilder(
                animation: _waveCtrl,
                builder: (_, _) => Row(
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

// ─── Chat input bar ───────────────────────────────────────────────────────────

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
  final SttModelManager _sttManager = SttModelManager();
  final CoachingSttService _stt = CoachingSttService();
  bool _listening = false;
  StreamSubscription<SttPartialResult>? _sttSub;

  bool get _sttAvail => _stt.isAvailable;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCtrlChanged);
    _initStt();
  }

  Future<void> _initStt() async {
    await _sttManager.downloadIfNeeded();
    final current = _sttManager.currentState;
    if (current is SttModelStateReady) {
      await _stt.initialize(current.modelDir);
      if (mounted) setState(() {});
    }
  }

  void _onCtrlChanged() => setState(() {});

  void _setListening(bool value) {
    if (!mounted) return;
    setState(() => _listening = value);
    widget.onRecordingChanged(value);
  }

  @override
  void dispose() {
    _sttSub?.cancel();
    _stt.dispose();
    _sttManager.dispose();
    widget.controller.removeListener(_onCtrlChanged);
    super.dispose();
  }

  void _startListening() {
    if (!_sttAvail || _listening) return;
    _setListening(true);
    _sttSub = _stt.startListening().listen(
      (result) {
        widget.controller.text = result.text;
        widget.controller.selection =
            TextSelection.fromPosition(TextPosition(offset: result.text.length));
        if (result.isFinal) _setListening(false);
      },
      onError: (_) => _setListening(false),
      onDone: () => _setListening(false),
    );
  }

  Future<void> _stopListening() async {
    await _sttSub?.cancel();
    _sttSub = null;
    await _stt.stopListening();
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
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => widget.onSend(),
              ),
            ),
            const SizedBox(width: 8),
            if (_sttAvail)
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

// ─── Error banner ─────────────────────────────────────────────────────────────

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
          const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.slaOverdueText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: AppColors.slaOverdueText),
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
