import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/db/member_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/models/patient.dart';
import '../../../core/theme/app_theme.dart';
import 'enrollment_repository.dart';
import 'models/household_enrollment_models.dart';
import 'widgets/enrollment_dropdown.dart';
import 'widgets/enrollment_input_field.dart';
import 'widgets/enrollment_sticky_bar.dart';

/// Member registration form for linking a new person to an **existing** household.
///
/// Mirrors Android's MemberRegistrationFragment (IS_MEMBER_REGISTRATION=true,
/// householdId already set). On submit calls
/// [EnrollmentRepository.submitStandaloneMember] which produces:
///   `households: []`
///   `householdMembers: [{householdId, householdReferenceId, ...}]`
///
/// Navigation params (via GoRouter `extra` as `Map<String, dynamic>`):
///   householdId           – household FHIR/server ID (HouseholdEntity.fhirId or .id)
///   householdReferenceId  – household local-ref UUID  (HouseholdEntity.id)
///   householdName         – display name
///   householdNo           – display number
///   villageId / villageName / subVillageId / subVillageName
class LinkMemberScreen extends StatefulWidget {
  const LinkMemberScreen({
    super.key,
    required this.householdId,
    required this.householdReferenceId,
    this.householdName,
    this.householdNo,
    this.villageId,
    this.villageName,
    this.subVillageId,
    this.subVillageName,
  });

  final String householdId;
  final String householdReferenceId;
  final String? householdName;
  final String? householdNo;
  final String? villageId;
  final String? villageName;
  final String? subVillageId;
  final String? subVillageName;

  @override
  State<LinkMemberScreen> createState() => _LinkMemberScreenState();
}

class _LinkMemberScreenState extends State<LinkMemberScreen> {
  final _nameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  String? _gender;
  String _idType = 'BRN';
  String? _maritalStatus;
  String _disabilityStatus = 'Absent';
  bool _mobileNotAvailable = false;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dobCtrl.dispose();
    _ageCtrl.dispose();
    _idCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  void _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) {
      _dobCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
      _ageCtrl.text = (now.difference(picked).inDays ~/ 365).toString();
    }
  }

  bool _validate() {
    if (_nameCtrl.text.trim().isEmpty || _gender == null || _maritalStatus == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(EnrollmentStrings.fieldRequired),
        duration: Duration(seconds: 2),
      ));
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthRepository>();
      final api = context.read<ApiClient>();
      final memberDao = context.read<MemberDao>();
      final patientDao = context.read<PatientDao>();

      final userId = await auth.userId() ?? 0;
      final userFhirId = await auth.userFhirId() ?? '';
      final orgId = await auth.organizationFhirId() ?? '';
      final deviceId = await auth.deviceId();

      final repo = EnrollmentRepository(api);
      final dob = _dobCtrl.text.trim();
      final age = int.tryParse(_ageCtrl.text) ?? 0;

      final member = HouseholdMember(
        name: _nameCtrl.text.trim(),
        age: age,
        gender: _gender!,
        dateOfBirth: dob,
        idType: _idType,
        idNumber: _idCtrl.text.isNotEmpty ? _idCtrl.text.trim() : null,
        mobileNumber: _mobileNotAvailable
            ? null
            : (_mobileCtrl.text.isNotEmpty ? _mobileCtrl.text.trim() : null),
        mobileAvailable: !_mobileNotAvailable,
        maritalStatus: _maritalStatus!,
        disabilityStatus: _disabilityStatus,
        relationshipToHead: 'Other',
      );

      // Use sub-village as canonical village (mirrors _memberToPatient in sync service).
      final canonicalVillageId =
          (widget.subVillageId?.isNotEmpty == true ? widget.subVillageId : null) ??
              widget.villageId ??
              '';
      final canonicalVillageName =
          (widget.subVillageName?.isNotEmpty == true ? widget.subVillageName : null) ??
              widget.villageName ??
              '';

      final result = await repo.submitStandaloneMember(
        member: member,
        householdId: widget.householdId,
        householdReferenceId: widget.householdReferenceId,
        villageName: canonicalVillageName,
        villageId: canonicalVillageId,
        subVillageId: widget.subVillageId,
        subVillageName: widget.subVillageName,
        userId: userId,
        userFhirId: userFhirId,
        organizationId: orgId,
        deviceId: deviceId,
      );

      // Persist locally so the member is visible immediately (offline-first).
      await _persistLocally(
        result: result,
        member: member,
        canonicalVillageId: canonicalVillageId,
        canonicalVillageName: canonicalVillageName,
        memberDao: memberDao,
        patientDao: patientDao,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(LinkMemberStrings.successMessage),
        ));
        context.go('/patients/households');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${LinkMemberStrings.errorPrefix}: $e'),
          duration: const Duration(seconds: 3),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persistLocally({
    required StandaloneMemberResult result,
    required HouseholdMember member,
    required String canonicalVillageId,
    required String canonicalVillageName,
    required MemberDao memberDao,
    required PatientDao patientDao,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final refId = result.memberReferenceId;

    await memberDao.upsertMany([
      HouseholdMemberEntity(
        id: refId,
        householdId: widget.householdId,
        householdReferenceId: widget.householdReferenceId,
        name: member.name,
        gender: member.gender,
        dob: member.dateOfBirth,
        phone: member.mobileNumber,
        nationalId: member.idNumber,
        idType: member.idType,
        villageId: canonicalVillageId,
        villageName: canonicalVillageName,
        subVillageId: widget.subVillageId,
        subVillageName: widget.subVillageName,
        maritalStatus: member.maritalStatus,
        disability: member.disabilityStatus.toLowerCase(),
        isHouseholdHead: false,
        isActive: true,
        isPregnant: false,
        createdAt: nowMs,
        updatedAt: nowMs,
        syncStatus: 'Success',
      ),
    ]);

    await patientDao.upsertMany([
      Patient(
        id: refId,
        name: member.name,
        gender: member.gender,
        dob: member.dateOfBirth,
        phone: member.mobileNumber,
        nationalId: member.idNumber,
        villageId: canonicalVillageId,
        villageName: canonicalVillageName,
        householdId: widget.householdId,
        isActive: true,
        updatedAt: nowMs,
        rawJson: jsonEncode({
          'id': refId,
          'name': member.name,
          'gender': member.gender,
          'dateOfBirth': member.dateOfBirth,
          'phoneNumber': member.mobileNumber,
          'nationalId': member.idNumber,
          'villageId': canonicalVillageId,
          'houseHoldId': widget.householdId,
          'isActive': true,
        }),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              LinkMemberStrings.title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              widget.householdName ?? widget.householdNo ?? '',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        toolbarHeight: 72,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Household context banner ─────────────────────────────────
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFBFDBFE), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Text('🏠', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${widget.householdName ?? LinkMemberStrings.selectedHouseholdLabel}'
                          '  •  ${widget.householdNo ?? ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Q1 Name ──────────────────────────────────────────────────
                _Q(number: 'Q1', text: EnrollmentStrings.memberNameLabel),
                const SizedBox(height: 8),
                EnrollmentInputField(
                  label: EnrollmentStrings.memberNameLabel,
                  hint: EnrollmentStrings.memberNameHint,
                  controller: _nameCtrl,
                ),
                const SizedBox(height: 20),

                // ── Q2 ID type + number ──────────────────────────────────────
                _Q(number: 'Q2', text: EnrollmentStrings.idTypeLabel),
                const SizedBox(height: 8),
                EnrollmentDropdown(
                  label: EnrollmentStrings.idTypeLabel,
                  value: _idType,
                  options: EnrollmentStrings.idTypes,
                  onChanged: (v) => setState(() => _idType = v ?? 'BRN'),
                ),
                const SizedBox(height: 10),
                EnrollmentInputField(
                  label: EnrollmentStrings.idNumberLabel,
                  hint: EnrollmentStrings.idNumberHint,
                  controller: _idCtrl,
                ),
                const SizedBox(height: 20),

                // ── Q3 Date of birth / age ────────────────────────────────────
                _Q(number: 'Q3', text: EnrollmentStrings.dateOfBirthLabel),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickDob,
                  child: AbsorbPointer(
                    child: EnrollmentInputField(
                      label: EnrollmentStrings.dateOfBirthLabel,
                      hint: EnrollmentStrings.dateOfBirthHint,
                      controller: _dobCtrl,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                EnrollmentInputField(
                  label: EnrollmentStrings.ageLabel,
                  hint: EnrollmentStrings.ageHint,
                  controller: _ageCtrl,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),

                // ── Q4 Gender ────────────────────────────────────────────────
                _Q(number: 'Q4', text: EnrollmentStrings.genderLabel),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: EnrollmentStrings.genders.map((g) {
                    final sel = _gender == g;
                    return GestureDetector(
                      onTap: () => setState(() => _gender = g),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.navy : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: sel
                                ? AppColors.navy
                                : const Color(0xFFD1D5DB),
                          ),
                        ),
                        child: Text(
                          g,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: sel
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // ── Q5 Marital status ─────────────────────────────────────────
                _Q(number: 'Q5', text: EnrollmentStrings.maritalStatusLabel),
                const SizedBox(height: 8),
                EnrollmentDropdown(
                  label: EnrollmentStrings.maritalStatusLabel,
                  value: _maritalStatus,
                  options: EnrollmentStrings.maritalStatuses,
                  onChanged: (v) => setState(() => _maritalStatus = v),
                ),
                const SizedBox(height: 20),

                // ── Q6 Disability ─────────────────────────────────────────────
                _Q(number: 'Q6', text: EnrollmentStrings.disabilityStatusLabel),
                const SizedBox(height: 8),
                EnrollmentDropdown(
                  label: EnrollmentStrings.disabilityStatusLabel,
                  value: _disabilityStatus,
                  options: EnrollmentStrings.disabilityStatusesV2,
                  onChanged: (v) =>
                      setState(() => _disabilityStatus = v ?? 'Absent'),
                ),
                const SizedBox(height: 20),

                // ── Q7 Mobile ─────────────────────────────────────────────────
                _Q(number: 'Q7', text: EnrollmentStrings.mobileNumberLabel),
                const SizedBox(height: 8),
                if (!_mobileNotAvailable)
                  EnrollmentInputField(
                    label: EnrollmentStrings.mobileNumberLabel,
                    hint: EnrollmentStrings.mobileNumberHint,
                    controller: _mobileCtrl,
                    keyboardType: TextInputType.phone,
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _mobileNotAvailable,
                        onChanged: (v) => setState(
                            () => _mobileNotAvailable = v ?? false),
                        activeColor: AppColors.navy,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      EnrollmentStrings.mobileNotAvailableHint,
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Sticky CTA ────────────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: EnrollmentStickyBar(
              label: _loading
                  ? LinkMemberStrings.submitting
                  : LinkMemberStrings.ctaLabel,
              onPressed: _loading ? () {} : _submit,
            ),
          ),
        ],
      ),
    );
  }
}

/// Numbered question label (e.g. "Q1 Full Name").
class _Q extends StatelessWidget {
  const _Q({required this.number, required this.text});
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$number ',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          TextSpan(
            text: text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
