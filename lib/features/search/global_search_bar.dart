import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../household/household_detail_screen.dart';
import 'global_search_repository.dart';
import 'household_search_repository.dart';
import 'member_search_repository.dart';

class GlobalSearchBar extends StatefulWidget {
  const GlobalSearchBar({super.key});

  @override
  State<GlobalSearchBar> createState() => _GlobalSearchBarState();
}

class _GlobalSearchBarState extends State<GlobalSearchBar> {
  final SearchController _controller = SearchController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SearchAnchor.bar(
      searchController: _controller,
      barHintText: SearchStrings.barHint,
      barLeading: const Icon(Icons.search),
      isFullScreen: true,
      suggestionsBuilder: (context, controller) {
        return [
          _SearchView(
            controller: controller,
            onClose: () => controller.closeView(controller.text),
          ),
        ];
      },
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView({required this.controller, required this.onClose});

  final SearchController controller;
  final VoidCallback onClose;

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  static const Duration _debounce = Duration(milliseconds: 350);

  Timer? _debounceTimer;
  int _token = 0;
  SearchScope _scope = SearchScope.all;
  String _lastQuery = '';
  bool _busy = false;
  GlobalSearchHits? _hits;
  String? _progressText;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onQueryChanged);
    if (widget.controller.text.isNotEmpty) {
      _scheduleSearch(widget.controller.text);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onQueryChanged);
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onQueryChanged() {
    _scheduleSearch(widget.controller.text);
  }

  void _scheduleSearch(String raw) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => _runSearch(raw));
  }

  Future<void> _runSearch(String raw) async {
    final q = raw.trim();
    final token = ++_token;
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _busy = false;
          _hits = null;
          _progressText = null;
          _error = null;
          _lastQuery = q;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
        _progressText = null;
        _lastQuery = q;
      });
    }
    try {
      final repo = context.read<GlobalSearchRepository>();
      final hits = await repo.search(
        query: q,
        scope: _scope,
        onMemberProgress: (p) {
          if (token == _token && mounted) {
            setState(() => _progressText = 'Scanning members ${p.loaded}/${p.cap}…');
          }
        },
        onHouseholdProgress: (p) {
          if (token == _token && mounted) {
            setState(() => _progressText = SearchStrings.scanningHouseholds(p.loaded, p.cap));
          }
        },
      );
      if (token != _token || !mounted) return;
      setState(() {
        _hits = hits;
        _busy = false;
      });
    } catch (e) {
      if (token != _token || !mounted) return;
      setState(() {
        _error = e;
        _busy = false;
      });
    }
  }

  void _setScope(SearchScope s) {
    if (s == _scope) return;
    setState(() => _scope = s);
    if (_lastQuery.isNotEmpty) _runSearch(_lastQuery);
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    // Use a SizedBox to provide bounded height since this widget is rendered
    // inside SearchAnchor's suggestionsBuilder (which uses a ListView).
    // Subtract approximate height for the search bar (~100) and status bar.
    final availableHeight = MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.top -
        kToolbarHeight -
        56; // search bar height
    return SizedBox(
      height: availableHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text(SearchStrings.scopeAll),
                  selected: _scope == SearchScope.all,
                  onSelected: (_) => _setScope(SearchScope.all),
                ),
                ChoiceChip(
                  label: const Text(SearchStrings.scopePatients),
                  selected: _scope == SearchScope.patients,
                  onSelected: (_) => _setScope(SearchScope.patients),
                ),
                ChoiceChip(
                  label: const Text(SearchStrings.scopeHouseholds),
                  selected: _scope == SearchScope.households,
                  onSelected: (_) => _setScope(SearchScope.households),
                ),
              ],
            ),
          ),
          if (_busy)
            const LinearProgressIndicator()
          else
            const SizedBox(height: 4),
          if (_busy && _progressText != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _progressText!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _body(context, hits)),
        ],
      ),
    );
  }

  Widget _failureView() {
    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(SearchStrings.searchFailed),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => _runSearch(_lastQuery),
            child: const Text(CommonStrings.retry),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, GlobalSearchHits? hits) {
    if (_error != null) {
      return _failureView();
    }
    if (_lastQuery.isEmpty) {
      return const _Centered(
        child: Text(
          SearchStrings.emptyPrompt,
          textAlign: TextAlign.center,
        ),
      );
    }
    if (hits == null) {
      return const SizedBox.shrink();
    }
    final showMembers = _scope != SearchScope.households;
    final showHouseholds = _scope != SearchScope.patients;
    if (hits.isEmpty && !_busy) {
      // Distinguish a failed search from a genuinely empty result.
      if (hits.error != null) return _failureView();
      return const _Centered(child: Text(SearchStrings.noMatches));
    }
    return ListView(
      children: [
        if (showMembers) ...[
          _SectionHeader(label: SearchStrings.scopePatients, count: hits.members.length),
          if (hits.members.isEmpty)
            const _EmptyRow(SearchStrings.noPatientMatches)
          else
            ...hits.members.map((m) => _MemberTile(
              hit: m,
              onTap: () => _navigateToMember(m),
            )),
          if (hits.membersTruncated)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text(SearchStrings.resultsCapped),
            ),
        ],
        if (showHouseholds) ...[
          _SectionHeader(label: SearchStrings.scopeHouseholds, count: hits.households.length),
          if (hits.households.isEmpty)
            const _EmptyRow(SearchStrings.noHouseholdMatches)
          else
            ...hits.households.map(
              (h) => _HouseholdTile(
                hit: h,
                onTap: () => _navigateToHousehold(h),
              ),
            ),
          if (hits.householdsTruncated)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text(SearchStrings.resultsCapped),
            ),
        ],
      ],
    );
  }

  void _navigateToMember(MemberHit hit) {
    widget.onClose();
    if (hit.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member ID not available')),
      );
      return;
    }
    // Use /patients/ directly (not /patient/) to avoid redirect that loses extra data
    context.push('/patients/${hit.id}', extra: {
      'id': hit.id,
      'name': hit.name,
      'age': hit.age != null ? int.tryParse(hit.age!) : null,
      'gender': hit.gender,
      'phoneNumber': hit.phone,
      'idCode': hit.nid,
      'householdId': hit.householdId,
      'householdName': hit.householdName,
      'householdNo': hit.householdNo,
    });
  }

  void _navigateToHousehold(HouseholdHit hit) {
    widget.onClose();
    if (hit.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Household ID not available')),
      );
      return;
    }
    // Convert to HouseholdDetailData for the detail screen
    final detailData = hit.rawJson != null
        ? HouseholdDetailData.fromJson(hit.rawJson!)
        : HouseholdDetailData(
            id: hit.id,
            name: hit.name,
            householdNo: hit.householdNo,
            village: hit.village,
            memberCount: hit.memberCount ?? 0,
            members: const [],
          );
    context.push('/household/${hit.id}', extra: detailData);
  }

}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        '$label  ·  $count',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.search_off, color: Colors.grey),
        title: Text(text, style: const TextStyle(color: Colors.grey)),
        dense: true,
      );
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.hit, required this.onTap});
  final MemberHit hit;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(hit.name ?? CommonStrings.unnamed),
      subtitle: Text([
        if (hit.age != null) SearchStrings.age(hit.age!),
        if (hit.phone != null) hit.phone!,
        if (hit.nid != null) SearchStrings.nid(hit.nid!),
        if (hit.householdName != null) hit.householdName!,
      ].join(' · ')),
      onTap: onTap,
    );
  }
}

class _HouseholdTile extends StatelessWidget {
  const _HouseholdTile({required this.hit, required this.onTap});
  final HouseholdHit hit;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.home)),
      title: Text(hit.name ?? CommonStrings.unnamed),
      subtitle: Text([
        if (hit.householdNo != null) SearchStrings.householdNo(hit.householdNo!),
        if (hit.village != null) hit.village!,
        if (hit.memberCount != null) SearchStrings.memberCount(hit.memberCount!),
      ].join(' · ')),
      onTap: onTap,
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: child),
      );
}
