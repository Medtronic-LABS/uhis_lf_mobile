import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/models/programme.dart';
import 'encounter_repository.dart';
import 'household_repository.dart';
import 'visit_controller.dart';

/// Data passed to visit landing screen.
class VisitLandingData {
  const VisitLandingData({
    required this.patientId,
    this.patientName,
    this.patientAge,
    this.patientGender,
    this.householdId,
    this.programme,
    this.origin,
  });

  final String patientId;
  final String? patientName;
  final int? patientAge;
  final String? patientGender;
  final String? householdId;
  final Programme? programme;
  /// Origin screen for return navigation ('dashboard' or 'tasks').
  final String? origin;
}

/// Visit Landing Screen — entry point for starting a visit.
///
/// Shows patient header, "Last seen X ago" line, greeting prompt,
/// household co-flags, and "Start Visit" CTA.
class VisitLandingScreen extends StatefulWidget {
  const VisitLandingScreen({
    super.key,
    required this.patientId,
    this.data,
  });

  final String patientId;
  final VisitLandingData? data;

  @override
  State<VisitLandingScreen> createState() => _VisitLandingScreenState();
}

class _VisitLandingScreenState extends State<VisitLandingScreen> {
  Future<VisitSummary?>? _lastVisitFuture;
  Future<List<HouseholdMemberFlag>>? _coFlagsFuture;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final encounterRepo = context.read<EncounterRepository>();
    final householdRepo = context.read<HouseholdRepository>();

    _lastVisitFuture = encounterRepo.lastEncounterSummary(widget.patientId);

    // First-time patients skip the landing screen — go straight to triage.
    _lastVisitFuture!.then((lastVisit) {
      if (lastVisit == null && mounted) {
        _startVisit();
      }
    });

    if (widget.data?.householdId != null) {
      _coFlagsFuture = householdRepo.coFlagsFor(
        widget.patientId,
        householdId: widget.data!.householdId,
      );
    }
  }

  Future<void> _startVisit() async {
    if (_starting) return;
    setState(() => _starting = true);

    final controller = context.read<VisitController>();
    final programme = widget.data?.programme ?? Programme.unknown;

    final encounterId = await controller.startVisit(
      patientId: widget.patientId,
      programme: programme,
      patientName: widget.data?.patientName,
      patientAge: widget.data?.patientAge,
      patientGender: widget.data?.patientGender,
      householdId: widget.data?.householdId,
    );

    if (!mounted) return;

    if (encounterId != null) {
      // Pass origin through to triage for return navigation
      final origin = widget.data?.origin;
      final originParam = origin != null ? '?origin=$origin' : '';
      debugPrint('[VisitLanding] navigating to triage with origin=$origin');
      context.go(
        '/patients/visit/$encounterId/flow$originParam',
        extra: {
          'patientId': widget.patientId,
          'patientName': widget.data?.patientName,
          'memberId': null,
          'householdId': widget.data?.householdId,
          'patientAge': widget.data?.patientAge,
          'patientGender': widget.data?.patientGender,
        },
      );
    } else {
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.error ?? VisitLandingStrings.startFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;

    return Scaffold(
      appBar: AppBar(
        title: const Text(PatientContextStrings.startVisit),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Patient Header Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data?.patientName ?? PatientContextStrings.fallbackTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (data?.patientAge != null)
                        VisitLandingStrings.ageYears(data!.patientAge!),
                      if (data?.patientGender != null) data!.patientGender,
                    ].join(' • '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (data?.programme != null) ...[
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(data!.programme!.wireTag),
                      backgroundColor: theme.colorScheme.primaryContainer,
                      labelStyle: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Last seen line
          FutureBuilder<VisitSummary?>(
            future: _lastVisitFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox.shrink();
              }
              final lastVisit = snapshot.data;
              if (lastVisit == null) {
                return Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline),
                        SizedBox(width: 12),
                        Text(VisitLandingStrings.firstVisit),
                      ],
                    ),
                  ),
                );
              }
              final daysSince = DateTime.now().difference(lastVisit.date).inDays;
              final timeAgo = daysSince == 0
                  ? VisitLandingStrings.seenToday
                  : daysSince == 1
                      ? VisitLandingStrings.seenYesterday
                      : daysSince < 7
                          ? VisitLandingStrings.seenDaysAgo(daysSince)
                          : VisitLandingStrings.seenWeeksAgo(
                              (daysSince / 7).floor());
              return Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          VisitLandingStrings.lastSeen(
                              timeAgo, lastVisit.programme.wireTag),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // Household co-flags
          if (_coFlagsFuture != null)
            FutureBuilder<List<HouseholdMemberFlag>>(
              future: _coFlagsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox.shrink();
                }
                final flags = snapshot.data ?? [];
                if (flags.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      VisitLandingStrings.alsoInHousehold,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...flags.map((member) => Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.errorContainer,
                              child: Icon(
                                Icons.warning_amber,
                                color: theme.colorScheme.error,
                              ),
                            ),
                            title: Text(member.name),
                            subtitle: Text(
                              member.flags.map((f) => f.label).join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),

          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _starting ? null : _startVisit,
            icon: _starting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_starting
                ? VisitLandingStrings.startingButton
                : PatientContextStrings.startVisit),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
        ),
      ),
    );
  }

}
