/// Full knowledge library screen — reached via "See all" from coaching tab.
///
/// Mock-only (no knowledge API approved). All content from [MockCoachingData.knowledgeDocs].
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_strings.dart';
import '../../core/debug/console_log.dart';
import 'coaching_models.dart';
import 'coaching_repository.dart';

const _kSpiceBlue = Color(0xFF2514BE);
const _kSpiceBlueContainer = Color(0xFFE8F0FE);
const _kMetaColor = Color(0xFF6B7280);
const _kTitleColor = Color(0xFF101828);

class KnowledgeListScreen extends StatelessWidget {
  const KnowledgeListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final docs = context.watch<CoachingRepository>().knowledgeDocs;
    ConsoleLog.step('[KnowledgeListScreen] docs=${docs.length}');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(CoachingStrings.knowledgeSection),
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
        itemCount: docs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => _KnowledgeListTile(doc: docs[i]),
      ),
    );
  }
}

class _KnowledgeListTile extends StatelessWidget {
  const _KnowledgeListTile({required this.doc});

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
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document not available'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ConsoleLog.warn('[KnowledgeListScreen] Could not open $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = doc.titleBn.isNotEmpty ? doc.titleBn : doc.titleEn;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  doc.thumbnailPresignedUrl != null
                      ? Image.network(
                          doc.thumbnailPresignedUrl!,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 52,
                            height: 52,
                            color: _kSpiceBlueContainer,
                            child: const Icon(Icons.description_rounded, color: _kSpiceBlue, size: 28),
                          ),
                        )
                      : Container(
                          width: 52,
                          height: 52,
                          color: _kSpiceBlueContainer,
                          child: const Icon(Icons.description_rounded, color: _kSpiceBlue, size: 28),
                        ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: _domainColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        _domainLabel,
                        style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kTitleColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _TypeBadge(label: doc.docType),
                      if (doc.pageCount != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          CoachingStrings.docTypePages(doc.pageCount!),
                          style: const TextStyle(fontSize: 11, color: _kMetaColor),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _kMetaColor),
          ],
        ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _kSpiceBlueContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _kSpiceBlue),
      ),
    );
  }
}
