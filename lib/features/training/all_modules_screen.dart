/// Full list of all training modules — reached via "See all" from the coaching tab.
library;

import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import 'coaching_models.dart';
import 'module_detail_screen.dart';

const _kSpiceBlue = Color(0xFF2514BE);
const _kSpiceBlueContainer = Color(0xFFE8F0FE);
const _kSpiceNavy = Color(0xFF1B2B5E);
const _kSpiceMid = Color(0xFF1565C0);
const _kMetaTextColor = Color(0xFF6B7280);

class AllModulesScreen extends StatelessWidget {
  const AllModulesScreen({super.key, required this.modules});

  final List<CoachingModule> modules;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(TrainingStrings.allModulesTitle),
        backgroundColor: _kSpiceBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: modules.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => _AllModulesTile(module: modules[i]),
      ),
    );
  }
}

class _AllModulesTile extends StatelessWidget {
  const _AllModulesTile({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    final title = module.titleBn.isNotEmpty ? module.titleBn : module.titleEn;
    final subtitle =
        '${module.estimatedMinutes} ${CoachingStrings.minLabel} · '
        '${module.quiz.length} ${CoachingStrings.detailQuestions}';

    return Opacity(
      opacity: module.isLocked ? 0.6 : 1.0,
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
        child: InkWell(
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
              MaterialPageRoute<void>(
                builder: (_) => ModuleDetailScreen(module: module),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: _kSpiceBlueContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _kSpiceNavy,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _kMetaTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _Ring(progress: module.progressFraction),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            color: _kSpiceMid,
            backgroundColor: _kSpiceBlueContainer,
            strokeWidth: 3,
          ),
          Text(
            '${(progress * 100).toInt()}%',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: _kSpiceMid,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}
