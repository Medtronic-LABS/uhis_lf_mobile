/// Training requests screen — CHW can view and submit training requests.
///
/// Mock-only (no training-request API approved). Submissions stored in-memory only.
library;

import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/debug/console_log.dart';
import 'coaching_models.dart';

const _kSpiceBlue = Color(0xFF2514BE);
const _kSpiceBlueContainer = Color(0xFFE8F0FE);
const _kMetaColor = Color(0xFF6B7280);

class TrainingRequestsScreen extends StatefulWidget {
  const TrainingRequestsScreen({super.key});

  @override
  State<TrainingRequestsScreen> createState() => _TrainingRequestsScreenState();
}

class _TrainingRequestsScreenState extends State<TrainingRequestsScreen> {
  late final List<TrainingRequest> _requests;

  @override
  void initState() {
    super.initState();
    _requests = List.of(MockCoachingData.trainingRequests);
    ConsoleLog.step('[TrainingRequestsScreen] requests=${_requests.length} (mock — no training-request API)');
  }

  void _addRequest(TrainingRequest req) {
    setState(() => _requests.insert(0, req));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(CoachingStrings.trainingRequestsSection),
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
      body: _requests.isEmpty
          ? Center(
              child: Text(
                CoachingStrings.noTrainingRequests,
                style: const TextStyle(color: _kMetaColor, fontSize: 14),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _requests.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) => _RequestTile(request: _requests[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRequestForm(context),
        backgroundColor: _kSpiceBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(CoachingStrings.requestTrainingCta),
      ),
    );
  }

  void _showRequestForm(BuildContext context) {
    showModalBottomSheet<TrainingRequest>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RequestFormSheet(onSubmit: _addRequest),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request});

  final TrainingRequest request;

  @override
  Widget build(BuildContext context) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final date = '${request.submittedAt.day} ${months[request.submittedAt.month - 1]} ${request.submittedAt.year}';

    Color statusColor;
    String statusLabel;
    switch (request.status) {
      case TrainingRequestStatus.approved:
        statusColor = const Color(0xFF2E7D52);
        statusLabel = CoachingStrings.requestStatusApproved;
      case TrainingRequestStatus.rejected:
        statusColor = const Color(0xFFD9534F);
        statusLabel = CoachingStrings.requestStatusRejected;
      case TrainingRequestStatus.pending:
        statusColor = const Color(0xFFF57C00);
        statusLabel = CoachingStrings.requestStatusPending;
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _kSpiceBlueContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.school_rounded, color: _kSpiceBlue, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.topic,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF101828)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (request.notes.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      request.notes,
                      style: const TextStyle(fontSize: 12, color: _kMetaColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(date, style: const TextStyle(fontSize: 11, color: _kMetaColor)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestFormSheet extends StatefulWidget {
  const _RequestFormSheet({required this.onSubmit});

  final void Function(TrainingRequest) onSubmit;

  @override
  State<_RequestFormSheet> createState() => _RequestFormSheetState();
}

class _RequestFormSheetState extends State<_RequestFormSheet> {
  final _topicCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _topicCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final req = TrainingRequest(
      id: 'tr_${DateTime.now().millisecondsSinceEpoch}',
      topic: _topicCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      submittedAt: DateTime.now(),
    );
    widget.onSubmit(req);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(CoachingStrings.requestSubmitted),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4E7EC),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              CoachingStrings.requestTrainingCta,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF101828)),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _topicCtrl,
              decoration: InputDecoration(
                hintText: CoachingStrings.requestTopicHint,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                hintText: CoachingStrings.requestNotesHint,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _kSpiceBlue,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(CoachingStrings.requestSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
