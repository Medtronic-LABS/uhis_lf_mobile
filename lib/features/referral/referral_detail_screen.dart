import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_strings.dart';
import '../../core/db/patient_dao.dart';
import '../../core/debug/console_log.dart';
import '../../core/models/patient.dart';
import '../../core/models/referral.dart';
import 'referral_api_service.dart';
import 'referral_repository.dart';
import 'widgets/notes_panel.dart';
import 'widgets/referral_card.dart';
import 'widgets/referral_timeline.dart';

/// `/patient/:id/referrals` — timeline view of every referral for a patient.
/// Enhanced with notes, audit trail, and action controls.
class ReferralDetailScreen extends StatefulWidget {
  const ReferralDetailScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<ReferralDetailScreen> createState() => _ReferralDetailScreenState();
}

class _ReferralDetailScreenState extends State<ReferralDetailScreen> 
    with SingleTickerProviderStateMixin {
  Future<_PatientReferrals>? _future;
  late TabController _tabController;
  
  // Cached references to avoid context.read on deactivated widget
  ReferralRepository? _repo;
  PatientDao? _patientDao;
  bool _listenerAdded = false;

  // Notes storage (in production, this would be fetched from API)
  final Map<String, List<ReferralNote>> _notesCache = {};

  @override
  void initState() {
    debugPrint('[_ReferralDetailScreenState] initState patientId=${widget.patientId}');
    super.initState();
    debugPrint('[_ReferralDetailScreenState] initState');
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache references - always refresh on didChangeDependencies
    _repo = context.read<ReferralRepository>();
    _patientDao = context.read<PatientDao>();
    // Initialize future and listener on first call
    if (!_listenerAdded) {
      _listenerAdded = true;
      _future = _load();
      _repo!.changes.addListener(_onChanges);
    }
  }

  @override
  void dispose() {
    debugPrint('[_ReferralDetailScreenState] dispose patientId=${widget.patientId}');
    _repo?.changes.removeListener(_onChanges);
    _tabController.dispose();
    debugPrint('[_ReferralDetailScreenState] dispose');
    super.dispose();
  }

  void _onChanges() {
    debugPrint('[_ReferralDetailScreenState] _onChanges patientId=${widget.patientId}');
    if (!mounted) return;
    _reload();
  }

  void _reload() {
    if (!mounted || _repo == null) return;
    final future = _load();
    setState(() {
      _future = future;
    });
  }

  Future<_PatientReferrals> _load() async {
    debugPrint('[_ReferralDetailScreenState] _load');
    final repo = _repo;
    final patientDao = _patientDao;
    // Return empty data if dependencies aren't ready
    if (repo == null || patientDao == null) {
      return _PatientReferrals(patient: null, referrals: const [], events: const {});
    }
    final patient = await patientDao.byId(widget.patientId);
    final all = await repo.load(); // load full set then filter; small N.
    final mine =
        all.where((r) => r.patientId == widget.patientId).toList(growable: false);
    final events = <String, List<ReferralStatusEventRow>>{};
    for (final r in mine) {
      events[r.id] = await repo.timeline(r.id);
    }
    return _PatientReferrals(patient: patient, referrals: mine, events: events);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(ReferralStrings.dashboardTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Timeline', icon: Icon(Icons.timeline_rounded)),
            Tab(text: 'Audit Trail', icon: Icon(Icons.history_rounded)),
          ],
        ),
      ),
      body: FutureBuilder<_PatientReferrals>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(snap.error.toString()));
          }
          final data = snap.data!;
          if (data.referrals.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.folder_open_rounded,
                        size: 48,
                        color: scheme.outline,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Referrals',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ReferralStrings.emptyBody,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // Timeline tab
              _buildTimelineView(data),
              // Audit trail tab
              _buildAuditTrailView(data),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNotesSheet(
          widget.patientId,
          _future?.then((d) => d.referrals.firstOrNull?.id) ?? Future.value(null),
        ),
        icon: const Icon(Icons.notes_rounded),
        label: const Text('Notes'),
      ),
    );
  }

  Widget _buildTimelineView(_PatientReferrals data) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: data.referrals.length,
      itemBuilder: (context, i) {
        final r = data.referrals[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReferralCard(
              referral: r,
              patientLabel: data.patient?.name ?? widget.patientId,
              patientAge: data.patient?.age,
              onTap: () {},
              onSeeWhy: () => _showRationaleSheet(r, data.patient),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 16, 16),
              child: ReferralTimeline(
                events: data.events[r.id] ?? const [],
                currentState: r.state,
                dueArrivalAt: r.dueArrivalAt,
                dueTreatmentAt: r.dueTreatmentAt,
                breachedSince: r.breachedSince,
              ),
            ),
            // Quick actions row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildQuickActions(r),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActions(Referral r) {
    final isOpen = !r.state.isClosed;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showNotesSheet(r.patientId, Future.value(r.id)),
            icon: const Icon(Icons.notes_rounded, size: 18),
            label: Text('Notes (${_notesCache[r.id]?.length ?? 0})'),
          ),
        ),
        const SizedBox(width: 8),
        if (isOpen) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _updateStatus(r),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Update'),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _showFullDetails(r),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Details'),
          ),
        ),
      ],
    );
  }

  Widget _buildAuditTrailView(_PatientReferrals data) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    
    // Combine all events from all referrals and sort by date
    final allEvents = <_AuditEvent>[];
    for (final r in data.referrals) {
      final events = data.events[r.id] ?? [];
      for (final e in events) {
        allEvents.add(_AuditEvent(
          referralId: r.id,
          event: e,
          diagnosis: r.diagnosisLabel,
        ));
      }
    }
    allEvents.sort((a, b) => b.event.occurredAt.compareTo(a.event.occurredAt));

    if (allEvents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 48, color: scheme.outline),
            const SizedBox(height: 16),
            Text('No audit trail', style: textTheme.titleMedium),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allEvents.length,
      itemBuilder: (context, i) {
        final item = allEvents[i];
        final e = item.event;
        final isStateChange = e.fromState != e.toState;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isStateChange
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerLow,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getEventIcon(e.toState),
                  size: 18,
                  color: isStateChange
                      ? scheme.onPrimaryContainer
                      : scheme.outline,
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _getEventTitle(e, isStateChange),
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          DateFormat.MMMd().add_jm().format(
                            DateTime.fromMillisecondsSinceEpoch(e.occurredAt),
                          ),
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (e.reason != null && e.reason!.isNotEmpty)
                      Text(
                        e.reason!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.person_outline, size: 14, color: scheme.outline),
                        const SizedBox(width: 4),
                        Text(
                          e.actor ?? 'System',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                        if (item.diagnosis != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.local_hospital_outlined, 
                               size: 14, color: scheme.outline),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.diagnosis!,
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.outline,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
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

  IconData _getEventIcon(ReferralStatus state) {
    switch (state) {
      case ReferralStatus.created:
        return Icons.add_circle_outline;
      case ReferralStatus.acknowledged:
        return Icons.check_circle_outline;
      case ReferralStatus.inTransit:
        return Icons.directions_car_outlined;
      case ReferralStatus.arrived:
        return Icons.location_on_outlined;
      case ReferralStatus.treatmentStarted:
        return Icons.medical_services_outlined;
      case ReferralStatus.closedRecovered:
        return Icons.check_circle;
      case ReferralStatus.closedDeceased:
        return Icons.cancel;
      case ReferralStatus.breachedArrival:
        return Icons.warning_amber_rounded;
      default:
        return Icons.info_outline;
    }
  }

  String _getEventTitle(ReferralStatusEventRow e, bool isStateChange) {
    if (isStateChange) {
      return '${_stateLabel(e.fromState)} → ${_stateLabel(e.toState)}';
    }
    return _stateLabel(e.toState);
  }

  String _stateLabel(ReferralStatus? state) {
    if (state == null) return 'Unknown';
    switch (state) {
      case ReferralStatus.created: return 'Created';
      case ReferralStatus.acknowledged: return 'Acknowledged';
      case ReferralStatus.inTransit: return 'In Transit';
      case ReferralStatus.arrived: return 'Arrived';
      case ReferralStatus.treatmentStarted: return 'Treatment Started';
      case ReferralStatus.closedRecovered: return 'Recovered';
      case ReferralStatus.closedDeceased: return 'Deceased';
      case ReferralStatus.breachedArrival: return 'SLA Breached';
      default: return state.wireTag;
    }
  }

  Future<void> _showNotesSheet(String patientId, Future<String?> referralIdFuture) async {
    final referralId = await referralIdFuture;
    if (referralId == null || !mounted) return;

    // Get or initialize notes for this referral
    _notesCache[referralId] ??= [];

    await NotesPanel.show(
      context,
      referralId: referralId,
      notes: _notesCache[referralId]!,
      onAddNote: (note) async {
        // Add note locally (in production, call API)
        final newNote = ReferralNote(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          referralId: referralId,
          content: note,
          createdAt: DateTime.now(),
          author: 'SK',
        );
        setState(() {
          _notesCache[referralId]!.add(newNote);
        });
        return true;
      },
    );
  }

  void _showRationaleSheet(Referral r, Patient? p) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ReferralStrings.rationaleSheetTitle,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              for (final d in r.priorityDrivers)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, size: 20, color: scheme.tertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ReferralStrings.formatDriver(d),
                          style: Theme.of(ctx).textTheme.bodyLarge,
                        ),
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

  Future<void> _updateStatus(Referral r) async {
    ConsoleLog.step('[Referral] opening outcome sheet for ${r.id}');
    final options = <({String label, String subtitle, ReferralStatus status, IconData icon, Color color})>[
      (
        label: ReferralStrings.outcomeReferred,
        subtitle: ReferralStrings.outcomeReferredSubtitle,
        status: ReferralStatus.created,
        icon: Icons.local_hospital_outlined,
        color: Colors.orange,
      ),
      (
        label: ReferralStrings.outcomeOnTreatment,
        subtitle: ReferralStrings.outcomeOnTreatmentSubtitle,
        status: ReferralStatus.treatmentStarted,
        icon: Icons.healing_outlined,
        color: Colors.blue,
      ),
      (
        label: ReferralStrings.outcomeRecovered,
        subtitle: ReferralStrings.outcomeRecoveredSubtitle,
        status: ReferralStatus.closedRecovered,
        icon: Icons.check_circle_outline,
        color: Colors.green,
      ),
      (
        label: ReferralStrings.outcomeDeceased,
        subtitle: ReferralStrings.outcomeDeceasedSubtitle,
        status: ReferralStatus.closedDeceased,
        icon: Icons.sentiment_very_dissatisfied_outlined,
        color: Colors.grey,
      ),
    ];

    final chosen = await showModalBottomSheet<ReferralStatus>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                ReferralStrings.recordOutcomeTitle,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                ReferralStrings.recordOutcomeSubtitle,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.outline,
                    ),
              ),
            ),
            ...options.map((opt) => ListTile(
                  leading: Icon(opt.icon, color: opt.color),
                  title: Text(opt.label,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(opt.subtitle),
                  selected: r.state == opt.status,
                  selectedTileColor:
                      opt.color.withValues(alpha: 0.08),
                  onTap: () => Navigator.of(ctx).pop(opt.status),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (chosen == null || !mounted) return;
    ConsoleLog.step('[Referral] status update: ${chosen.wireTag} for ${r.id}');
    try {
      await _repo!.transition(referralId: r.id, to: chosen);
      ConsoleLog.success('[Referral] status updated to ${chosen.wireTag}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ReferralStrings.outcomeUpdated)),
        );
      }
    } catch (e) {
      ConsoleLog.warn('[Referral] status update failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ReferralStrings.outcomeUpdateFailed)),
        );
      }
    }
  }

  void _showFullDetails(Referral r) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening full details...')),
    );
  }
}

class _PatientReferrals {
  const _PatientReferrals({
    required this.patient,
    required this.referrals,
    required this.events,
  });

  final Patient? patient;
  final List<Referral> referrals;
  final Map<String, List<ReferralStatusEventRow>> events;
}

/// Helper class for audit trail display.
class _AuditEvent {
  const _AuditEvent({
    required this.referralId,
    required this.event,
    this.diagnosis,
  });

  final String referralId;
  final ReferralStatusEventRow event;
  final String? diagnosis;
}
