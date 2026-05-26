import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'patient_search_repository.dart';

class PatientSearchScreen extends StatefulWidget {
  const PatientSearchScreen({super.key});

  @override
  State<PatientSearchScreen> createState() => _PatientSearchScreenState();
}

class _PatientSearchScreenState extends State<PatientSearchScreen> {
  final _ctl = TextEditingController();
  PatientSearchField _field = PatientSearchField.name;
  Future<List<PatientHit>>? _future;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _go() {
    final q = _ctl.text.trim();
    if (q.isEmpty) {
      setState(() => _future = Future.value(const []));
      return;
    }
    final repo = context.read<PatientSearchRepository>();
    setState(() => _future = repo.search(field: _field, query: q));
  }

  String _hint() {
    switch (_field) {
      case PatientSearchField.name:
        return 'e.g. Aisha';
      case PatientSearchField.phone:
        return 'e.g. 9123';
      case PatientSearchField.nid:
        return 'e.g. NID12345';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search patients')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _ctl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _go(),
              decoration: InputDecoration(
                hintText: _hint(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _go,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                for (final f in PatientSearchField.values) ...[
                  ChoiceChip(
                    label: Text({
                      PatientSearchField.name: 'Name',
                      PatientSearchField.phone: 'Phone',
                      PatientSearchField.nid: 'NID',
                    }[f]!),
                    selected: _field == f,
                    onSelected: (_) => setState(() => _field = f),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _future == null
                ? const _EmptyState(text: 'Type a query and tap Search')
                : FutureBuilder<List<PatientHit>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return _ErrorState(
                          message: 'Search failed — try again.',
                          onRetry: _go,
                        );
                      }
                      final hits = snap.data ?? const <PatientHit>[];
                      if (hits.isEmpty) {
                        return const _EmptyState(text: 'No patients matched.');
                      }
                      return ListView.separated(
                        itemCount: hits.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final h = hits[i];
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(h.name ?? '(unnamed)'),
                            subtitle: Text([
                              if (h.age != null) 'Age ${h.age}',
                              if (h.phone != null) h.phone!,
                              if (h.nid != null) 'NID ${h.nid}',
                            ].join(' · ')),
                            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Patient detail not implemented'),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
