import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/constants/app_strings.dart';
import '../../core/models/programme.dart';
import '../../core/models/risk.dart';
import 'member_detail_repository.dart';
import 'open_followups_section.dart';
import 'patient_actions_row.dart';
import 'patient_repository.dart';
import 'recent_vitals_section.dart';
import 'visit_details_screen.dart';

/// Combined data type that can hold either a local patient or remote member.
class PatientOrMemberData {
  const PatientOrMemberData({
    this.localPatient,
    this.remoteMember,
    this.programmes = const {},
    this.remoteAssessments = const [],
    this.recentVisits = const [],
    this.memberId,
  });

  final PatientWithProgrammes? localPatient;
  final MemberHealthDetails? remoteMember;
  final Set<Programme> programmes;
  final List<MemberAssessment> remoteAssessments;
  final List<PatientVisit> recentVisits;
  final String? memberId;

  bool get hasData => localPatient != null || remoteMember != null;

  String? get name => localPatient?.patient.name ?? remoteMember?.name;
  String? get gender => localPatient?.patient.gender ?? remoteMember?.gender;
  String? get householdId =>
      localPatient?.patient.householdId ?? remoteMember?.householdId;
  String? get villageId =>
      localPatient?.patient.villageId ?? remoteMember?.villageId;
  String? get phoneNumber =>
      localPatient?.patient.phone ?? remoteMember?.phoneNumber;
  String? get patientId =>
      localPatient?.patient.patientId ?? remoteMember?.patientId;
  int? get age => localPatient?.patient.age ?? remoteMember?.age;
  bool get isPregnant => remoteMember?.isPregnant ?? false;
  int? get riskScore => localPatient?.patient.riskScore;
  RiskBand? get riskBand => localPatient?.patient.riskBand;
  List<String> get riskReasons => localPatient?.patient.riskReasons ?? [];
  List<MemberAssessment> get assessments => 
      remoteAssessments.isNotEmpty ? remoteAssessments : (remoteMember?.assessments ?? []);
  
  /// Member reference for FHIR API calls (format: RelatedPerson/xxx).
  String? get memberReference {
    final id = memberId ?? remoteMember?.id;
    if (id == null) return null;
    if (id.startsWith('RelatedPerson/')) return id;
    return 'RelatedPerson/$id';
  }
}

/// Patient/Member Context Screen — shows health details when tapping on a
/// patient from the worklist or a member from household details.
class PatientContextScreen extends StatefulWidget {
  const PatientContextScreen({
    super.key,
    required this.patientId,
    this.memberData,
  });

  final String patientId;
  /// Pre-populated member data passed from household detail.
  /// If provided, skips remote lookup when local patient not found.
  final Map<String, dynamic>? memberData;

  @override
  State<PatientContextScreen> createState() => _PatientContextScreenState();
}

class _PatientContextScreenState extends State<PatientContextScreen> {
  Future<PatientOrMemberData>? _future;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Initialize directly without setState since widget isn't mounted yet
    _future = _fetchData();
  }

  void _load() {
    final future = _fetchData();
    setState(() {
      _future = future;
    });
  }

  Future<PatientOrMemberData> _fetchData() async {
    // ignore: avoid_print
    print('[PatientContextScreen] _fetchData for patientId: ${widget.patientId}');
    
    final memberRepo = context.read<MemberDetailRepository>();
    final authRepo = context.read<AuthRepository>();
    
    // Get user's assigned sub-village IDs for assessment queries
    final subVillageIds = await authRepo.subVillageIds();
    final userVillageId = subVillageIds.isNotEmpty ? subVillageIds.first.toString() : null;
    // ignore: avoid_print
    print('[PatientContextScreen] User subVillageIds: $subVillageIds, using: $userVillageId');
    
    // First try local patient database
    final patientRepo = context.read<PatientRepository>();
    final localPatient = await patientRepo.byId(widget.patientId);
    if (localPatient != null) {
      // ignore: avoid_print
      print('[PatientContextScreen] Found local patient: ${localPatient.patient.name}');
      
      // Also fetch assessments from remote API using user's sub-village ID
      // ignore: avoid_print
      print('[PatientContextScreen] Fetching assessments from remote API with villageId: $userVillageId...');
      final assessments = await memberRepo.getMemberAssessments(
        widget.patientId,
        villageId: userVillageId,
        patientAge: localPatient.patient.age,
        patientGender: localPatient.patient.gender,
      );
      // ignore: avoid_print
      print('[PatientContextScreen] Found ${assessments.length} remote assessments');
      
      // Fetch recent visits
      final patientIdForVisits = localPatient.patient.patientId ?? widget.patientId;
      final memberRef = 'RelatedPerson/${widget.patientId}';
      // ignore: avoid_print
      print('[PatientContextScreen] Fetching recent visits for patient: $patientIdForVisits, member: $memberRef, householdId: ${localPatient.patient.householdId}');
      final visits = await memberRepo.getRecentVisits(
        patientIdForVisits,
        memberReference: memberRef,
        householdId: localPatient.patient.householdId,
      );
      // ignore: avoid_print
      print('[PatientContextScreen] Found ${visits.length} recent visits');
      
      return PatientOrMemberData(
        localPatient: localPatient,
        programmes: localPatient.programmes,
        remoteAssessments: assessments,
        recentVisits: visits,
        memberId: widget.patientId,
      );
    }

    // ignore: avoid_print
    print('[PatientContextScreen] No local patient, trying remote member API');
    
    // If not found locally, try fetching member from remote API
    final member = await memberRepo.getMemberWithAssessments(widget.patientId);
    if (member != null) {
      // ignore: avoid_print
      print('[PatientContextScreen] Found remote member: ${member.name} with ${member.assessments.length} assessments');
      // Determine programmes from assessments
      final progs = <Programme>{};
      for (final a in member.assessments) {
        switch (a.type) {
          case 'ANC':
            progs.add(Programme.anc);
            break;
          case 'IMCI':
            progs.add(Programme.imci);
            break;
          case 'NCD':
            progs.add(Programme.ncd);
            break;
          case 'TB':
            progs.add(Programme.tb);
            break;
        }
      }
      
      // Fetch recent visits
      final patientIdForVisits = member.patientId ?? widget.patientId;
      final memberRef = 'RelatedPerson/${member.id}';
      // ignore: avoid_print
      print('[PatientContextScreen] Fetching recent visits for patient: $patientIdForVisits, member: $memberRef, householdId: ${member.householdId}');
      final visits = await memberRepo.getRecentVisits(
        patientIdForVisits,
        memberReference: memberRef,
        householdId: member.householdId,
      );
      // ignore: avoid_print
      print('[PatientContextScreen] Found ${visits.length} recent visits');
      
      return PatientOrMemberData(
        remoteMember: member,
        programmes: progs,
        recentVisits: visits,
        memberId: member.id,
      );
    }

    // If we have pre-passed member data from household detail, use it
    if (widget.memberData != null) {
      // ignore: avoid_print
      print('[PatientContextScreen] Using pre-passed member data from household');
      final data = widget.memberData!;
      // Extract patient profile for filtering
      final age = data['age'] as int?;
      final gender = data['gender'] as String?;
      final isPregnant = data['isPregnant'] as bool? ?? false;
      // Fetch assessments for this member using user's sub-village ID
      final assessments = await memberRepo.getMemberAssessments(
        widget.patientId,
        villageId: userVillageId,
        patientAge: age,
        patientGender: gender,
        isPregnant: isPregnant,
      );
      // ignore: avoid_print
      print('[PatientContextScreen] Found ${assessments.length} assessments for pre-passed member');
      
      // Determine programmes from assessments
      final progs = <Programme>{};
      for (final a in assessments) {
        switch (a.type) {
          case 'ANC':
            progs.add(Programme.anc);
            break;
          case 'IMCI':
            progs.add(Programme.imci);
            break;
          case 'NCD':
            progs.add(Programme.ncd);
            break;
          case 'TB':
            progs.add(Programme.tb);
            break;
        }
      }
      
      // Fetch recent visits
      final patientIdForVisits = data['patientId'] as String? ?? widget.patientId;
      final memberId = data['id']?.toString() ?? widget.patientId;
      final memberRef = 'RelatedPerson/$memberId';
      final householdIdForVisits = data['householdId']?.toString();
      // ignore: avoid_print
      print('[PatientContextScreen] Fetching recent visits for patient: $patientIdForVisits, member: $memberRef, householdId: $householdIdForVisits');
      final visits = await memberRepo.getRecentVisits(
        patientIdForVisits,
        memberReference: memberRef,
        householdId: householdIdForVisits,
      );
      // ignore: avoid_print
      print('[PatientContextScreen] Found ${visits.length} recent visits');
      
      return PatientOrMemberData(
        remoteMember: MemberHealthDetails(
          id: memberId,
          name: data['name'] as String? ?? 'Unknown',
          gender: data['gender'] as String?,
          age: data['age'] as int?,
          dateOfBirth: data['dateOfBirth'] as String?,
          phoneNumber: data['phoneNumber'] as String?,
          householdId: data['householdId']?.toString(),
          isPregnant: data['isPregnant'] as bool? ?? false,
          patientId: data['patientId'] as String?,
          assessments: assessments,
        ),
        programmes: progs,
        remoteAssessments: assessments,
        recentVisits: visits,
        memberId: memberId,
      );
    }

    // ignore: avoid_print
    print('[PatientContextScreen] No member found either');
    return const PatientOrMemberData();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final data = await _fetchData();
      if (!mounted) return;
      setState(() => _future = Future.value(data));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(PatientContextStrings.refreshDone)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(PatientContextStrings.refreshFailed)),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<PatientOrMemberData>(
          future: _future,
          builder: (context, snap) {
            final name = snap.data?.name;
            return Text(name ?? PatientContextStrings.fallbackTitle);
          },
        ),
        actions: [
          IconButton(
            tooltip: PatientContextStrings.refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
      ),
      body: FutureBuilder<PatientOrMemberData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data;
          if (data == null || !data.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_search_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      PatientContextStrings.notFound,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.tonal(
                      onPressed: _load,
                      child: const Text(CommonStrings.retry),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeaderCardV2(data: data, patientId: widget.patientId),
              const SizedBox(height: 16),
              if (data.riskReasons.isNotEmpty)
                _RationaleCard(reasons: data.riskReasons),
              if (data.riskReasons.isNotEmpty) const SizedBox(height: 16),
              // Show recent visits (from patientvisit/list endpoint)
              _RecentVisitsSection(
                visits: data.recentVisits,
                patientName: data.name,
              ),
              const SizedBox(height: 16),
              _AssessmentsSection(assessments: data.assessments),
              const SizedBox(height: 16),
              RecentVitalsSection(
                patientId: widget.patientId,
                memberReference: data.memberReference,
              ),
              const SizedBox(height: 16),
              OpenFollowupsSection(patientId: widget.patientId),
              const SizedBox(height: 16),
              PatientActionsRow(
                patientId: widget.patientId,
                patientName: data.name,
                patientAge: data.age,
                patientGender: data.gender,
                householdId: data.householdId,
                programmes: data.programmes,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.data, required this.patientId});

  final PatientWithProgrammes data;
  final String patientId;

  @override
  Widget build(BuildContext context) {
    final p = data.patient;
    final scheme = Theme.of(context).colorScheme;
    final progColors = Theme.of(context).extension<ProgrammeColors>()!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.name ?? PatientContextStrings.fallbackTitle,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            _kvRow(context, PatientContextStrings.idLabel, patientId),
            if (p.householdId != null)
              _kvRow(context, PatientContextStrings.householdLabel, p.householdId!),
            if (p.villageId != null)
              _kvRow(context, PatientContextStrings.villageLabel, p.villageId!),
            if (p.riskScore != null && p.riskBand != null)
              _kvRow(
                context,
                PatientContextStrings.riskLabel,
                '${_bandLabel(p.riskBand!)} · ${p.riskScore}',
              ),
            if (data.programmes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                PatientContextStrings.programmesLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final prog in data.programmes)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: progColors.containerOf(prog),
                        borderRadius: BorderRadius.circular(999),
                        border:
                            Border.all(color: progColors.of(prog)),
                      ),
                      child: Text(
                        _programmeLabel(prog),
                        style: TextStyle(
                          color: progColors.of(prog),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kvRow(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  static String _bandLabel(RiskBand band) {
    switch (band) {
      case RiskBand.urgent:
        return WorklistStrings.bandUrgent;
      case RiskBand.high:
        return WorklistStrings.bandHigh;
      case RiskBand.moderate:
        return WorklistStrings.bandModerate;
      case RiskBand.low:
        return WorklistStrings.bandLow;
    }
  }

  static String _programmeLabel(Programme p) {
    switch (p) {
      case Programme.imci:
        return WorklistStrings.programmeImci;
      case Programme.anc:
        return WorklistStrings.programmeAnc;
      case Programme.pnc:
        return WorklistStrings.programmePnc;
      case Programme.ncd:
        return WorklistStrings.programmeNcd;
      case Programme.tb:
        return WorklistStrings.programmeTb;
      case Programme.unknown:
        return WorklistStrings.programmeUnknown;
    }
  }
}

class _RationaleCard extends StatelessWidget {
  const _RationaleCard({required this.reasons});
  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              WorklistStrings.rationaleHeader,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            for (final r in reasons)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(r)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(
          PatientContextStrings.comingSoon,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        trailing: const Icon(Icons.lock_clock_outlined),
      ),
    );
  }
}

/// Header card for the unified PatientOrMemberData type.
class _HeaderCardV2 extends StatelessWidget {
  const _HeaderCardV2({required this.data, required this.patientId});

  final PatientOrMemberData data;
  final String patientId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progColors = Theme.of(context).extension<ProgrammeColors>()!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    Icons.person,
                    size: 28,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.name ?? PatientContextStrings.fallbackTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (data.age != null || data.gender != null)
                        Text(
                          [
                            if (data.age != null) '${data.age} years',
                            if (data.gender != null) data.gender,
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
                if (data.isPregnant)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pregnant_woman, size: 16, color: scheme.onTertiaryContainer),
                        const SizedBox(width: 4),
                        Text(
                          'Pregnant',
                          style: TextStyle(
                            color: scheme.onTertiaryContainer,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (data.patientId != null)
              _kvRow(context, PatientContextStrings.idLabel, data.patientId!),
            if (data.phoneNumber != null)
              _kvRow(context, 'Phone', data.phoneNumber!),
            if (data.householdId != null)
              _kvRow(context, PatientContextStrings.householdLabel, data.householdId!),
            if (data.villageId != null)
              _kvRow(context, PatientContextStrings.villageLabel, data.villageId!),
            if (data.riskScore != null && data.riskBand != null)
              _kvRow(
                context,
                PatientContextStrings.riskLabel,
                '${_bandLabel(data.riskBand!)} · ${data.riskScore}',
              ),
            if (data.programmes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                PatientContextStrings.programmesLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final prog in data.programmes)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: progColors.containerOf(prog),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: progColors.of(prog)),
                      ),
                      child: Text(
                        _programmeLabel(prog),
                        style: TextStyle(
                          color: progColors.of(prog),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kvRow(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  static String _bandLabel(RiskBand band) {
    switch (band) {
      case RiskBand.urgent:
        return WorklistStrings.bandUrgent;
      case RiskBand.high:
        return WorklistStrings.bandHigh;
      case RiskBand.moderate:
        return WorklistStrings.bandModerate;
      case RiskBand.low:
        return WorklistStrings.bandLow;
    }
  }

  static String _programmeLabel(Programme p) {
    switch (p) {
      case Programme.imci:
        return WorklistStrings.programmeImci;
      case Programme.anc:
        return WorklistStrings.programmeAnc;
      case Programme.pnc:
        return WorklistStrings.programmePnc;
      case Programme.ncd:
        return WorklistStrings.programmeNcd;
      case Programme.tb:
        return WorklistStrings.programmeTb;
      case Programme.unknown:
        return WorklistStrings.programmeUnknown;
    }
  }
}

/// Section showing recent patient visits from /spice-service/patientvisit/list.
class _RecentVisitsSection extends StatelessWidget {
  const _RecentVisitsSection({
    required this.visits,
    this.patientName,
  });

  final List<PatientVisit> visits;
  final String? patientName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('MMM d, yyyy');

    if (visits.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Recent Visits',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.event_busy_outlined,
                      size: 48,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No visits recorded yet',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Recent Visits',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                Text(
                  '${visits.length} total',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...visits.take(5).map((v) => _VisitTile(
                  visit: v,
                  dateFormat: dateFormat,
                  patientName: patientName,
                )),
          ],
        ),
      ),
    );
  }
}

class _VisitTile extends StatelessWidget {
  const _VisitTile({
    required this.visit,
    required this.dateFormat,
    this.patientName,
  });

  final PatientVisit visit;
  final DateFormat dateFormat;
  final String? patientName;

  void _navigateToDetails(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VisitDetailsScreen(
          visit: visit,
          patientName: patientName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => _navigateToDetails(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.local_hospital_outlined,
                size: 20,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (visit.serviceProvided != null ||
                          visit.encounterType != null)
                        Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          visit.serviceProvided ??
                              visit.encounterType ??
                              'Visit',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    if (visit.visitNumber != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Visit ${visit.visitNumber}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  dateFormat.format(visit.visitDate),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                if (visit.providerName != null)
                  Text(
                    'By ${visit.providerName}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
              ],
            ),
          ),
          if (visit.status != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                visit.status!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          // Chevron to indicate tappable
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
        ],
        ),
      ),
    );
  }
}

/// Section showing assessment history.
class _AssessmentsSection extends StatelessWidget {
  const _AssessmentsSection({required this.assessments});

  final List<MemberAssessment> assessments;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('MMM d, yyyy');

    if (assessments.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.assignment_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    PatientContextStrings.sectionRecentVisits,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.history_outlined,
                      size: 48,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No assessments yet',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  PatientContextStrings.sectionRecentVisits,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                Text(
                  '${assessments.length} total',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...assessments.take(5).map((a) => _AssessmentTile(
                  assessment: a,
                  dateFormat: dateFormat,
                )),
            if (assessments.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton(
                    onPressed: () {
                      // TODO: Show full assessment list
                    },
                    child: Text('View all ${assessments.length} assessments'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile({
    required this.assessment,
    required this.dateFormat,
  });

  final MemberAssessment assessment;
  final DateFormat dateFormat;

  void _showAssessmentDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AssessmentDetailSheet(
        assessment: assessment,
        dateFormat: dateFormat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progColors = Theme.of(context).extension<ProgrammeColors>()!;

    Color typeColor;
    IconData typeIcon;
    switch (assessment.type) {
      case 'ANC':
        typeColor = progColors.of(Programme.anc);
        typeIcon = Icons.pregnant_woman;
        break;
      case 'IMCI':
        typeColor = progColors.of(Programme.imci);
        typeIcon = Icons.child_care;
        break;
      case 'NCD':
        typeColor = progColors.of(Programme.ncd);
        typeIcon = Icons.monitor_heart_outlined;
        break;
      case 'TB':
        typeColor = progColors.of(Programme.tb);
        typeIcon = Icons.healing;
        break;
      default:
        typeColor = scheme.primary;
        typeIcon = Icons.assignment;
    }

    return InkWell(
      onTap: () => _showAssessmentDetail(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(typeIcon, size: 20, color: typeColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          assessment.type,
                          style: TextStyle(
                            color: typeColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      if (assessment.visitNumber != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          'Visit ${assessment.visitNumber}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateFormat.format(assessment.date),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet showing assessment details.
class _AssessmentDetailSheet extends StatelessWidget {
  const _AssessmentDetailSheet({
    required this.assessment,
    required this.dateFormat,
  });

  final MemberAssessment assessment;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progColors = Theme.of(context).extension<ProgrammeColors>()!;
    final raw = assessment.rawJson;
    
    Color typeColor;
    IconData typeIcon;
    switch (assessment.type) {
      case 'ANC':
        typeColor = progColors.of(Programme.anc);
        typeIcon = Icons.pregnant_woman;
        break;
      case 'IMCI':
        typeColor = progColors.of(Programme.imci);
        typeIcon = Icons.child_care;
        break;
      case 'NCD':
        typeColor = progColors.of(Programme.ncd);
        typeIcon = Icons.monitor_heart_outlined;
        break;
      case 'TB':
        typeColor = progColors.of(Programme.tb);
        typeIcon = Icons.healing;
        break;
      default:
        typeColor = scheme.primary;
        typeIcon = Icons.assignment;
    }

    // Extract useful fields from rawJson
    final visitDate = raw['visitDate']?.toString();
    final serviceProvided = raw['serviceProvided']?.toString();
    final referralStatus = raw['referralStatus']?.toString();
    final referralReason = raw['referralReason']?.toString();
    final nextFollowUpDate = raw['nextFollowUpDate']?.toString();
    final memberId = raw['householdMemberId']?.toString();
    final encounterId = raw['encounterId']?.toString();
    final latestVisit = raw['latestVisit'] == true;
    final customStatus = raw['customStatus'] as List<dynamic>?;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(typeIcon, size: 28, color: typeColor),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  assessment.type,
                                  style: TextStyle(
                                    color: typeColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (latestVisit) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Latest',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Visit on ${dateFormat.format(assessment.date)}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _DetailRow(label: 'Service', value: serviceProvided ?? assessment.type),
                    if (assessment.visitNumber != null)
                      _DetailRow(label: 'Visit Number', value: '${assessment.visitNumber}'),
                    if (encounterId != null)
                      _DetailRow(label: 'Encounter ID', value: encounterId),
                    if (memberId != null)
                      _DetailRow(label: 'Member ID', value: memberId),
                    if (referralStatus != null && referralStatus.isNotEmpty)
                      _DetailRow(
                        label: 'Referral Status',
                        value: referralStatus,
                        valueColor: referralStatus.toLowerCase() == 'referred' ? Colors.orange : null,
                      ),
                    if (referralReason != null && referralReason.isNotEmpty)
                      _DetailRow(label: 'Referral Reason', value: referralReason),
                    if (nextFollowUpDate != null && nextFollowUpDate.isNotEmpty)
                      _DetailRow(label: 'Next Follow-up', value: nextFollowUpDate),
                    if (customStatus != null && customStatus.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Status Indicators',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: customStatus.map((s) => Chip(
                          label: Text(s.toString()),
                          backgroundColor: typeColor.withValues(alpha: 0.1),
                          labelStyle: TextStyle(color: typeColor, fontSize: 12),
                        )).toList(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    // Assessment type specific info
                    _buildTypeSpecificInfo(context, typeColor),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypeSpecificInfo(BuildContext context, Color typeColor) {
    final scheme = Theme.of(context).colorScheme;
    
    switch (assessment.type) {
      case 'ANC':
        return Card(
          color: typeColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.pregnant_woman, color: typeColor),
                    const SizedBox(width: 8),
                    Text(
                      'Antenatal Care Visit',
                      style: TextStyle(
                        color: typeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'This visit included routine prenatal checkups, fetal monitoring, and maternal health assessment.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      case 'IMCI':
        return Card(
          color: typeColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.child_care, color: typeColor),
                    const SizedBox(width: 8),
                    Text(
                      'Child Health Visit',
                      style: TextStyle(
                        color: typeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Integrated Management of Childhood Illness assessment including growth monitoring, immunization status, and illness screening.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      case 'NCD':
        return Card(
          color: typeColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.monitor_heart_outlined, color: typeColor),
                    const SizedBox(width: 8),
                    Text(
                      'NCD Screening',
                      style: TextStyle(
                        color: typeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Non-communicable disease screening including blood pressure, glucose levels, and cardiovascular risk assessment.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      case 'TB':
        return Card(
          color: typeColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.healing, color: typeColor),
                    const SizedBox(width: 8),
                    Text(
                      'TB Screening',
                      style: TextStyle(
                        color: typeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Tuberculosis screening including symptom assessment, contact tracing, and treatment monitoring.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
