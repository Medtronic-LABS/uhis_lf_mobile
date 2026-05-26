import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'household_search_repository.dart';

class HouseholdSearchScreen extends StatefulWidget {
  const HouseholdSearchScreen({super.key});

  @override
  State<HouseholdSearchScreen> createState() => _HouseholdSearchScreenState();
}

class _HouseholdSearchScreenState extends State<HouseholdSearchScreen> {
  final _ctl = TextEditingController();
  HouseholdSearchField _field = HouseholdSearchField.name;
  bool _busy = false;
  HouseholdSearchResult? _result;
  Object? _error;
  HouseholdSearchProgress? _progress;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final q = _ctl.text.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
      _progress = null;
    });
    try {
      final repo = context.read<HouseholdSearchRepository>();
      final r = await repo.search(
        field: _field,
        query: q,
        onProgress: (p) => mounted ? setState(() => _progress = p) : null,
      );
      if (!mounted) return;
      setState(() => _result = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search households')),
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
                hintText: _field == HouseholdSearchField.name
                    ? 'household name e.g. Khatun'
                    : 'household no e.g. HH-001',
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
                ChoiceChip(
                  label: const Text('Name'),
                  selected: _field == HouseholdSearchField.name,
                  onSelected: (_) =>
                      setState(() => _field = HouseholdSearchField.name),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Household No'),
                  selected: _field == HouseholdSearchField.householdNo,
                  onSelected: (_) =>
                      setState(() => _field = HouseholdSearchField.householdNo),
                ),
              ],
            ),
          ),
          if (_busy && _progress != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scanned ${_progress!.loaded}/${_progress!.cap}…'),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: _progress!.cap == 0
                        ? null
                        : _progress!.loaded / _progress!.cap,
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_busy && _result == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Search failed — try again.'),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _go, child: const Text('Retry')),
          ],
        ),
      );
    }
    final r = _result;
    if (r == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Type a query and tap Search'),
        ),
      );
    }
    if (r.matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No households matched. (Scanned ${r.totalScanned}.)',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: r.matches.length + (r.truncated ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        if (r.truncated && i == r.matches.length) {
          return const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Result list capped — refine your query'),
          );
        }
        final h = r.matches[i];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.home)),
          title: Text(h.name ?? '(unnamed)'),
          subtitle: Text([
            if (h.householdNo != null) 'No ${h.householdNo}',
            if (h.village != null) h.village!,
            if (h.memberCount != null) '${h.memberCount} members',
          ].join(' · ')),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Household detail not implemented')),
          ),
        );
      },
    );
  }
}
