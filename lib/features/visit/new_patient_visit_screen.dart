import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api/scribe_api_service.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/models/programme.dart';
import '../../core/theme/app_theme.dart';
import '../realtime_asr/chief_complaint_matcher.dart';
import '../scribe/scribe_controller.dart';
import '../scribe/scribe_permission_service.dart';
import '../scribe/widgets/ai_scribe_banner.dart';
import 'symptom_catalog.dart';
import 'visit_controller.dart';
import 'visit_flow_header.dart';
import 'visit_start_helper.dart';

/// Which service the SK is selecting for this visit.
enum _Svc { pw, anc, pnc, fp, general, ncd }

/// First-time visit screen — symptom picker + eligible service grid.
/// Shown when a patient has no prior encounter (no programme enrolled yet).
/// Matches the Priya Rani Das wireframe from apon_sushashthya_v13.html.
class NewPatientVisitScreen extends StatefulWidget {
  const NewPatientVisitScreen({
    super.key,
    required this.patientId,
    this.patientName,
    this.patientAge,
    this.patientGender,
    this.householdId,
    this.villageName,
    this.origin,
  });

  final String patientId;
  final String? patientName;
  final int? patientAge;
  final String? patientGender;
  final String? householdId;
  final String? villageName;
  final String? origin;

  @override
  State<NewPatientVisitScreen> createState() => _NewPatientVisitScreenState();
}

class _NewPatientVisitScreenState extends State<NewPatientVisitScreen> {
  bool _pwSelected = false;
  final Set<_Svc> _selectedSvcs = {};
  final Set<String> _selectedSymptoms = {};
  String _searchQuery = '';
  bool _starting = false;

  // ── gender / age helpers ──────────────────────────────────────────────────

  bool get _isFemale {
    final g = (widget.patientGender ?? '').toUpperCase().trim();
    return g.startsWith('F') || g == 'W' || g == 'WOMAN';
  }

  int? get _ageOrNull => widget.patientAge;
  int get _age => widget.patientAge ?? 0;

  bool get _showPregnancySection =>
      _isFemale && (_ageOrNull == null || (_age >= 10 && _age <= 49));

  bool get _showNcd => _ageOrNull == null || _age >= 18;

  bool get _showImci => _ageOrNull != null && _age < 5;

  // ── symptom list ──────────────────────────────────────────────────────────

  List<SymptomDef> get _symptomList {
    if (_selectedSvcs.contains(_Svc.anc) || _selectedSvcs.contains(_Svc.pnc)) {
      return SymptomCatalog.ancSymptoms;
    }
    if (_selectedSvcs.contains(_Svc.ncd)) return SymptomCatalog.ncdSymptoms;
    if (_showPregnancySection) return SymptomCatalog.ancSymptoms;
    if (_showImci) return SymptomCatalog.imciSymptoms;
    if (_showNcd) return SymptomCatalog.ncdSymptoms;
    return SymptomCatalog.ncdSymptoms;
  }

  List<SymptomDef> get _filteredSymptoms {
    if (_searchQuery.isEmpty) return _symptomList;
    final q = _searchQuery.toLowerCase();
    return _symptomList.where((s) => s.label.toLowerCase().contains(q)).toList();
  }

  // ── service helpers ───────────────────────────────────────────────────────

  Programme _toProgram(_Svc svc) {
    switch (svc) {
      case _Svc.anc:
        return Programme.anc;
      case _Svc.pnc:
        return Programme.pnc;
      case _Svc.fp:
        return Programme.familyPlanning;
      case _Svc.ncd:
        return Programme.ncd;
      case _Svc.general:
        return Programme.unknown;
      case _Svc.pw:
        return Programme.pw;
    }
  }

  bool _isLocked(_Svc svc) =>
      (svc == _Svc.anc || svc == _Svc.pnc) && !_pwSelected;

  void _onSvcTap(_Svc svc) {
    debugPrint('[_NewPatientVisitScreenState] _onSvcTap svc=${svc}');
    if (svc == _Svc.pw) {
      setState(() {
        _pwSelected = !_pwSelected;
        if (!_pwSelected) {
          _selectedSvcs.remove(_Svc.anc);
          _selectedSvcs.remove(_Svc.pnc);
        }
      });
      return;
    }
    if (_isLocked(svc)) {
      final msg = svc == _Svc.anc
          ? EnrollStrings.lockedToastAnc
          : EnrollStrings.lockedToastPnc;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    setState(() {
      if (_selectedSvcs.contains(svc)) {
        _selectedSvcs.remove(svc);
      } else {
        _selectedSvcs.add(svc);
      }
    });
  }

  // ── start visit ───────────────────────────────────────────────────────────

  Future<void> _startVisit() async {
    if (_starting) return;
    if (!_pwSelected && _selectedSvcs.isEmpty) return;
    setState(() => _starting = true);

    try {
      // PW always goes first so pwProfile renders before ANC clinical sections.
      final programmes = <Programme>[
        if (_pwSelected) Programme.pw,
        ..._selectedSvcs
            .map(_toProgram)
            .where((p) => p != Programme.unknown),
      ];
      final programme = programmes.isNotEmpty ? programmes.first : Programme.unknown;

      // Pregnancy data (LMP / EDD / obstetric history) is collected inline
      // inside the unified ANC form — do not show the registration sheet here.

      // Programme is NOT written here — writing at enrolment start would persist
      // the programme even if the SK abandons the visit mid-form. The write is
      // deferred to VisitFormScreen._onSectionedSubmit() so it only commits on
      // successful assessment submission.
      debugPrint(
        '[NewPatientVisit] deferred programme write: ${programmes.map((p) => p.name).join(',')} '
        'for patientId=${widget.patientId}',
      );

      if (!mounted) return;

      final controller = context.read<VisitController>();
      final encounterId = await startOrResumeVisit(
        context,
        controller: controller,
        patientId: widget.patientId,
        programme: programme,
        patientName: widget.patientName,
        patientAge: widget.patientAge,
        patientGender: widget.patientGender,
        householdId: widget.householdId,
      );

      if (!mounted) return;

      if (encounterId != null) {
        // Resolve memberId + villageId from local DB so the offline-sync
        // payload matches Android: encounter.memberId = numeric referenceId,
        // assessment.villageId = patient's sub-village scope.
        String? resolvedMemberId;
        String? resolvedVillageId;
        int? resolvedLocalId;
        if (mounted) {
          final patientDao = context.read<PatientDao>();
          final memberDao = context.read<MemberDao>();
          final patient = await patientDao.byId(widget.patientId);
          resolvedVillageId = patient?.villageId;

          // Mirror PatientContextScreen._resolveEncounterMemberId():
          // prefer numeric referenceId from member entity.
          final entity = await memberDao.getById(widget.patientId) ??
              await memberDao.getByPatientId(widget.patientId);
          if (entity != null) {
            if (entity.referenceId?.isNotEmpty == true) {
              resolvedMemberId = entity.referenceId;
              resolvedLocalId = int.tryParse(entity.referenceId!);
            } else if (int.tryParse(entity.id) != null) {
              resolvedMemberId = entity.id;
              resolvedLocalId = int.tryParse(entity.id);
            }
          }
          // Fallback: patientId itself when member not yet in local DB
          // (e.g. freshly enrolled via household enrollment).
          resolvedMemberId ??= widget.patientId;
        }

        if (!mounted) return;

        final origin = widget.origin;
        final originParam = origin != null ? '?origin=$origin' : '';
        // Symptom selection already done on this screen — start flow at step 1
        // (programme recommendation + clinical form), skip the symptom picker.
        context.go(
          '/patients/visit/$encounterId/flow$originParam',
          extra: <String, dynamic>{
            'patientId': widget.patientId,
            'patientName': widget.patientName,
            'memberId': resolvedMemberId,
            'householdId': widget.householdId,
            'villageId': resolvedVillageId,
            'householdMemberLocalId': ?resolvedLocalId,
            'patientAge': widget.patientAge,
            'patientGender': widget.patientGender,
            'initialStep': 1,
            if (programmes.isNotEmpty)
              'seedProgrammes': programmes.map((p) => p.name).toList(),
          },
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(controller.error ?? VisitLandingStrings.startFailed),
            ),
          );
          setState(() => _starting = false);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _starting = false);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final name = widget.patientName ?? 'Patient';

    return ChangeNotifierProvider<ScribeController>(
      create: (ctx) => ScribeController(
        api: ctx.read<ScribeApiService>(),
        permissionService: ScribePermissionService(),
      ),
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: VisitFlowHeader.statusBarStyle,
          child: Column(
        children: [
          VisitFlowHeader(
            step: 0,
            patientId: widget.patientId,
            patientName: name,
            ageDisplay: widget.patientAge != null ? '${widget.patientAge}y' : null,
            householdId: widget.householdId,
            patientGender: widget.patientGender,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
          _SymptomSection(
            patientId: widget.patientId,
            isFemale: _isFemale,
            filteredSymptoms: _filteredSymptoms,
            selectedSymptoms: _selectedSymptoms,
            onSearchChanged: (v) => setState(() => _searchQuery = v),
            onSymptomToggle: (code) => setState(() {
              if (_selectedSymptoms.contains(code)) {
                _selectedSymptoms.remove(code);
              } else {
                _selectedSymptoms.add(code);
              }
            }),
          ),
          const SizedBox(height: 20),
          _ServicesSection(
            showPregnancySection: _showPregnancySection,
            showNcd: _showNcd,
            showImci: _showImci,
            pwSelected: _pwSelected,
            selectedSvcs: _selectedSvcs,
            onSvcTap: _onSvcTap,
          ),
        ],
      ),
          ),
        ],
      ),
        ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _Cta(
            selectedSvcs: _selectedSvcs,
            pwSelected: _pwSelected,
            starting: _starting,
            onTap: _startVisit,
          ),
        ),
      ),
    ),
    );
  }
}

// ── Symptom section ───────────────────────────────────────────────────────────

class _SymptomSection extends StatelessWidget {
  const _SymptomSection({
    required this.patientId,
    required this.isFemale,
    required this.filteredSymptoms,
    required this.selectedSymptoms,
    required this.onSearchChanged,
    required this.onSymptomToggle,
  });

  final String patientId;
  final bool isFemale;
  final List<SymptomDef> filteredSymptoms;
  final Set<String> selectedSymptoms;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSymptomToggle;

  void _applyScribeSymptoms(Set<String> codes) {
    for (final code in codes) {
      if (!selectedSymptoms.contains(code)) {
        onSymptomToggle(code);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final heading = isFemale
        ? NewPatientVisitStrings.howFeelFemale
        : NewPatientVisitStrings.howFeelMale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 10),
        // Live AI Scribe banner — same widget as Step 1 (SymptomPickerScreen).
        // patientId doubles as encounterId (live ASR doesn't use it for upload).
        if (AppConfig.scribeEnabled)
          AiScribeBanner(
            encounterId: patientId,
            patientId: patientId,
            isFemale: isFemale,
            tapStartsLiveAsr: true,
            onReviewReady: (ctrl) {
              final result = ctrl.session.triageExtractionResult;
              if (result != null) {
                _applyScribeSymptoms(result.symptomCodes.map((f) => f.fieldId).toSet());
              }
              ctrl.resetSession();
            },
            onLiveFields: (fields, _) {
              if (fields.chiefComplaints.isEmpty) return;
              final codes = ChiefComplaintMatcher.match(fields.chiefComplaints);
              if (codes.isEmpty) return;
              _applyScribeSymptoms(codes.toSet());
            },
          ),
        const SizedBox(height: 12),
        // Symptom picker card — matches _UnifiedSymptomPicker style
        Container(
          decoration: BoxDecoration(
            color: AppColors.textOnNavy,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: NewPatientVisitStrings.searchHint,
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.navy),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: AppColors.canvas,
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 14),
              if (filteredSymptoms.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    NewPatientVisitStrings.noSymptomsFound,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: filteredSymptoms.map((s) {
                    final isSelected = selectedSymptoms.contains(s.code);
                    return _SymptomChip(
                      symptom: s,
                      isSelected: isSelected,
                      onTap: () => onSymptomToggle(s.code),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }
}

/// Symptom chip matching the _PickerChip visual style from SymptomPickerScreen.
///
/// Unselected: white bg + grey border + navy text.
/// Selected:   navy bg + white check icon + white text.
/// Danger sign selected: red bg + white text (clinical safety signal).
class _SymptomChip extends StatelessWidget {
  const _SymptomChip({
    required this.symptom,
    required this.isSelected,
    required this.onTap,
  });

  final SymptomDef symptom;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDanger = symptom.isDangerSign;

    final Color bg;
    final Color borderColor;
    final Color textColor;

    if (isSelected) {
      if (isDanger) {
        bg = const Color(0xFFDC2626);
        borderColor = const Color(0xFFDC2626);
        textColor = Colors.white;
      } else {
        bg = AppColors.navy;
        borderColor = AppColors.navy;
        textColor = Colors.white;
      }
    } else {
      bg = Colors.white;
      borderColor = const Color(0xFFD1D5DB);
      textColor = AppColors.navy;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(
                isDanger ? Icons.warning_amber_rounded : Icons.check_rounded,
                size: 13,
                color: textColor,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              symptom.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Services section ──────────────────────────────────────────────────────────

class _ServicesSection extends StatelessWidget {
  const _ServicesSection({
    required this.showPregnancySection,
    required this.showNcd,
    required this.showImci,
    required this.pwSelected,
    required this.selectedSvcs,
    required this.onSvcTap,
  });

  final bool showPregnancySection;
  final bool showNcd;
  final bool showImci;
  final bool pwSelected;
  final Set<_Svc> selectedSvcs;
  final ValueChanged<_Svc> onSvcTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              NewPatientVisitStrings.eligibleServicesHeader,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE9FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                NewPatientVisitStrings.eligibleServicesTag,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF7C3AED),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ServiceGrid(
          showPregnancySection: showPregnancySection,
          showNcd: showNcd,
          showImci: showImci,
          pwSelected: pwSelected,
          selectedSvcs: selectedSvcs,
          onSvcTap: onSvcTap,
        ),
        if (!pwSelected && showPregnancySection) ...[
          const SizedBox(height: 8),
          const Center(
            child: Text(
              NewPatientVisitStrings.pwHint,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Service grid ──────────────────────────────────────────────────────────────

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({
    required this.showPregnancySection,
    required this.showNcd,
    required this.showImci,
    required this.pwSelected,
    required this.selectedSvcs,
    required this.onSvcTap,
  });

  final bool showPregnancySection;
  final bool showNcd;
  final bool showImci;
  final bool pwSelected;
  final Set<_Svc> selectedSvcs;
  final ValueChanged<_Svc> onSvcTap;

  @override
  Widget build(BuildContext context) {
    final specs = <_SvcSpec>[];

    if (showPregnancySection) {
      specs.add(const _SvcSpec(_Svc.pw, '🤰', 'PW', isPrereq: true));
      specs.add(_SvcSpec(_Svc.anc, '🏥', 'ANC', locked: !pwSelected));
      specs.add(const _SvcSpec(_Svc.fp, '🌸', 'FP'));
      specs.add(_SvcSpec(_Svc.pnc, '👶', 'PNC', locked: !pwSelected));
      specs.add(const _SvcSpec(_Svc.general, '🩺', 'General'));
      if (showNcd) specs.add(const _SvcSpec(_Svc.ncd, '💊', 'NCD'));
    } else if (showImci) {
      specs.add(const _SvcSpec(_Svc.general, '🩺', 'General'));
      if (showNcd) specs.add(const _SvcSpec(_Svc.ncd, '💊', 'NCD'));
    } else {
      specs.add(const _SvcSpec(_Svc.general, '🩺', 'General'));
      if (showNcd) specs.add(const _SvcSpec(_Svc.ncd, '💊', 'NCD'));
    }

    // Pad to multiple of 3
    while (specs.length % 3 != 0) {
      specs.add(const _SvcSpec(null, '', ''));
    }

    final rows = <Widget>[];
    for (var i = 0; i < specs.length; i += 3) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              for (var j = 0; j < 3; j++) ...[
                if (j > 0) const SizedBox(width: 10),
                Expanded(
                  child: specs[i + j].svc == null
                      ? const SizedBox.shrink()
                      : _SvcTile(
                          spec: specs[i + j],
                          selected: specs[i + j].isPrereq
                              ? pwSelected
                              : selectedSvcs.contains(specs[i + j].svc),
                          onTap: () => onSvcTap(specs[i + j].svc!),
                        ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }
}

class _SvcSpec {
  const _SvcSpec(
    this.svc,
    this.emoji,
    this.label, {
    this.isPrereq = false,
    this.locked = false,
  });

  final _Svc? svc;
  final String emoji;
  final String label;
  final bool isPrereq;
  final bool locked;
}

class _SvcTile extends StatelessWidget {
  const _SvcTile({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _SvcSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locked = spec.locked;

    final Color borderColor;
    final Color bgColor;
    final Color textColor;

    if (locked) {
      borderColor = AppColors.border;
      bgColor = AppColors.canvas;
      textColor = AppColors.textMuted;
    } else if (selected) {
      borderColor = AppColors.navy;
      bgColor = const Color(0xFFEBEEF5);
      textColor = AppColors.navy;
    } else {
      borderColor = AppColors.border;
      bgColor = Colors.white;
      textColor = const Color(0xFF374151);
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(spec.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    spec.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
            if (!locked)
              Positioned(
                top: 0,
                right: 6,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.navy : Colors.transparent,
                    border: Border.all(
                      color: selected ? AppColors.navy : const Color(0xFFD1D5DB),
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 9, color: Colors.white)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── CTA button ────────────────────────────────────────────────────────────────

class _Cta extends StatelessWidget {
  const _Cta({
    required this.selectedSvcs,
    required this.pwSelected,
    required this.starting,
    required this.onTap,
  });

  final Set<_Svc> selectedSvcs;
  final bool pwSelected;
  final bool starting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final canStart = !starting && (selectedSvcs.isNotEmpty || pwSelected);

    return FilledButton(
      onPressed: canStart ? onTap : null,
      style: FilledButton.styleFrom(
        backgroundColor:
            canStart ? AppColors.pink : const Color(0xFFD1D5DB),
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: starting
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              !canStart
                  ? NewPatientVisitStrings.selectServiceCta
                  : (pwSelected && selectedSvcs.isEmpty)
                      ? PregnancyRegStrings.registerCta
                      : NewPatientVisitStrings.startVisitCta,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
    );
  }
}
