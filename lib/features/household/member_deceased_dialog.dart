import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/db/pregnancy_snapshot_dao.dart';
import '../../core/rmnch/deceased_reason.dart';
import '../../core/sync/offline_push_service.dart';
import 'enrollment/enrollment_dob.dart';
import 'enrollment/widgets/enrollment_input_field.dart';
import 'member_deceased_service.dart';

/// Household summary flow for marking a member deceased — mirrors Android
/// `MemberDeceasedDialogFragment`, styled like enrollment forms.
Future<bool?> showMemberDeceasedDialog(
  BuildContext context, {
  required List<HouseholdMemberEntity> activeMembers,
}) {
  if (activeMembers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(MemberDeceasedStrings.noActiveMembers)),
    );
    return Future.value(null);
  }
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (ctx) => _MemberDeceasedDialog(activeMembers: activeMembers),
  );
}

String _titleCase(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

String _memberDisplayLabel(HouseholdMemberEntity m) {
  final name = _titleCase(m.name?.trim().isNotEmpty == true
      ? m.name!.trim()
      : MemberDeceasedStrings.unnamed);
  final ageLabel = EnrollmentAge.compactChipLabel(m.dob);
  final gender = m.gender?.trim().toLowerCase();
  String? genderInitial;
  if (gender != null && gender.isNotEmpty) {
    if (gender.startsWith('f')) {
      genderInitial = 'F';
    } else if (gender.startsWith('m')) {
      genderInitial = 'M';
    } else {
      genderInitial = gender[0].toUpperCase();
    }
  }
  final suffix = ageLabel != null && genderInitial != null
      ? '$ageLabel/$genderInitial'
      : ageLabel ?? genderInitial;
  return suffix != null ? '$name $suffix' : name;
}

/// Styled dropdown — same visual language as [EnrollmentDropdown].
class _DeceasedDropdown extends StatelessWidget {
  const _DeceasedDropdown({
    required this.label,
    required this.hint,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String hint;
  final String? value;
  final List<String> options;
  final String Function(String id) optionLabel;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  static const _labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textMuted,
    fontFamily: AppFonts.body,
  );

  static const _fieldStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    fontFamily: AppFonts.body,
  );

  static const _hintStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    fontFamily: AppFonts.body,
  );

  @override
  Widget build(BuildContext context) {
    final selected = value != null && options.contains(value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: _labelStyle),
            const Padding(
              padding: EdgeInsets.only(left: 3),
              child: Text(
                '*',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.statusCritical,
                  fontFamily: AppFonts.body,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.only(left: AppSpacing.xxxl),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            border: Border.all(color: AppColors.border, width: 1.5),
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: selected,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  hint: Text(hint, style: _hintStyle),
                  icon: selected != null
                      ? const SizedBox.shrink()
                      : const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                  style: _fieldStyle,
                  dropdownColor: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  selectedItemBuilder: (context) => options
                      .map(
                        (id) => Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            optionLabel(id),
                            overflow: TextOverflow.ellipsis,
                            style: _fieldStyle,
                          ),
                        ),
                      )
                      .toList(),
                  items: options
                      .map(
                        (id) => DropdownMenuItem<String>(
                          value: id,
                          child: Text(optionLabel(id), style: _fieldStyle),
                        ),
                      )
                      .toList(),
                  onChanged: enabled ? onChanged : null,
                ),
              ),
              if (selected != null && enabled)
                GestureDetector(
                  onTap: () => onChanged(null),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textMuted.withValues(alpha: 0.7),
                    ),
                  ),
                )
              else
                const SizedBox(width: AppSpacing.xxxl),
            ],
          ),
        ),
      ],
    );
  }
}

class _MemberDeceasedDialog extends StatefulWidget {
  const _MemberDeceasedDialog({required this.activeMembers});

  final List<HouseholdMemberEntity> activeMembers;

  @override
  State<_MemberDeceasedDialog> createState() => _MemberDeceasedDialogState();
}

enum _DeceasedFlow { initial, neonatal, maternal, freeText }

class _MemberDeceasedDialogState extends State<_MemberDeceasedDialog> {
  String? _selectedMemberId;
  _DeceasedFlow _flow = _DeceasedFlow.initial;
  String? _typeId;
  final _reasonController = TextEditingController();
  final Set<String> _selectedCauses = {};
  bool _submitting = false;
  bool _evaluatingMember = false;

  HouseholdMemberEntity? get _selected {
    if (_selectedMemberId == null) return null;
    for (final m in widget.activeMembers) {
      if (m.id == _selectedMemberId) return m;
    }
    return null;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _onMemberSelected(String? memberId) async {
    setState(() {
      _selectedMemberId = memberId;
      _flow = _DeceasedFlow.initial;
      _typeId = null;
      _selectedCauses.clear();
      _reasonController.clear();
      _evaluatingMember = memberId != null;
    });
    if (memberId == null) {
      setState(() => _evaluatingMember = false);
      return;
    }

    final member = _selected;
    if (member == null) {
      setState(() => _evaluatingMember = false);
      return;
    }

    final isNeonate = DeceasedReason.isNeonate(member.dob);
    var isMaternalCase = false;
    if (!isNeonate &&
        (member.gender?.toLowerCase() == 'female' ||
            member.gender?.toLowerCase() == 'f')) {
      final snapshotDao = context.read<PregnancySnapshotDao>();
      final patientKey = member.patientId ?? member.id;
      final snap = await snapshotDao.byPatientOrMember(
        patientKey,
        memberId: member.id,
      );
      isMaternalCase =
          DeceasedReason.isRecentDelivery(snap?.deliveryDateMillis);
    }

    if (!mounted || _selectedMemberId != memberId) return;
    setState(() {
      _evaluatingMember = false;
      if (isNeonate) {
        _flow = _DeceasedFlow.neonatal;
      } else if (isMaternalCase) {
        _flow = _DeceasedFlow.maternal;
      } else {
        _flow = _DeceasedFlow.freeText;
      }
    });
  }

  bool get _canSubmit {
    if (_selected == null || _submitting || _evaluatingMember) return false;
    if (_flow == _DeceasedFlow.freeText) {
      return _reasonController.text.trim().isNotEmpty;
    }
    if (_typeId == null || _typeId!.isEmpty) return false;
    if (_typeId == DeceasedReason.deathTypeOther) {
      return _reasonController.text.trim().isNotEmpty;
    }
    return _selectedCauses.isNotEmpty;
  }

  Future<void> _submit() async {
    if (!_canSubmit || _selected == null) return;
    setState(() => _submitting = true);
    final payload = DeceasedReason.buildPayload(
      typeId: _typeId,
      freeTextReason: _reasonController.text,
      selectedCauseIds: _selectedCauses.toList(),
    );
    final service = MemberDeceasedService(
      memberDao: context.read<MemberDao>(),
      patientDao: context.read<PatientDao>(),
      pushService: context.read<OfflinePushService>(),
    );
    final ok = await service.markDeceased(
      memberLocalId: _selected!.id,
      deceasedReason: payload,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(MemberDeceasedStrings.submitFailed)),
      );
    }
  }

  List<DeathTypeOption> get _typeOptions => switch (_flow) {
        _DeceasedFlow.neonatal => DeceasedReason.neonatalDeathTypeOptions,
        _DeceasedFlow.maternal => DeceasedReason.maternalDeathTypeOptions,
        _ => const [],
      };

  List<DeathCauseOption> get _causeOptions {
    if (_typeId == DeceasedReason.deathTypeNeonatal) {
      return DeceasedReason.neonatalDeathCauseOptions;
    }
    if (_typeId == DeceasedReason.deathTypeMother) {
      return DeceasedReason.maternalDeathCauseOptions;
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final memberIds = widget.activeMembers.map((m) => m.id).toList();
    final typeIds = _typeOptions.map((t) => t.id).toList();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: 420,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.h5xl,
            AppSpacing.xxxl,
            AppSpacing.h5xl,
            AppSpacing.xxxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      MemberDeceasedStrings.title,
                      style: AppTextStyles.aiTitle,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textMuted,
                      size: 22,
                    ),
                    onPressed: _submitting ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DeceasedDropdown(
                        label: MemberDeceasedStrings.selectMember,
                        hint: MemberDeceasedStrings.pleaseSelect,
                        value: _selectedMemberId,
                        options: memberIds,
                        optionLabel: (id) {
                          for (final m in widget.activeMembers) {
                            if (m.id == id) return _memberDisplayLabel(m);
                          }
                          return id;
                        },
                        onChanged: _onMemberSelected,
                        enabled: !_submitting,
                      ),
                      if (_evaluatingMember) ...[
                        const SizedBox(height: AppSpacing.xxxl),
                        const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                      if (_flow == _DeceasedFlow.neonatal ||
                          _flow == _DeceasedFlow.maternal) ...[
                        const SizedBox(height: AppSpacing.xxxl),
                        _DeceasedDropdown(
                          label: MemberDeceasedStrings.typeOfDeath,
                          hint: MemberDeceasedStrings.pleaseSelect,
                          value: _typeId,
                          options: typeIds,
                          optionLabel: (id) {
                            for (final t in _typeOptions) {
                              if (t.id == id) return t.label;
                            }
                            return id;
                          },
                          onChanged: (v) => setState(() {
                            _typeId = v;
                            _selectedCauses.clear();
                            _reasonController.clear();
                          }),
                          enabled: !_submitting,
                        ),
                      ],
                      if (_typeId == DeceasedReason.deathTypeNeonatal ||
                          _typeId == DeceasedReason.deathTypeMother) ...[
                        const SizedBox(height: AppSpacing.xxxl),
                        Text(
                          MemberDeceasedStrings.causeOfDeath,
                          style: _DeceasedDropdown._labelStyle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          MemberDeceasedStrings.causeHint,
                          style: AppTextStyles.subText,
                        ),
                        const SizedBox(height: 4),
                        ..._causeOptions.map(
                          (cause) => Theme(
                            data: Theme.of(context).copyWith(
                              unselectedWidgetColor: AppColors.textMuted,
                            ),
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                cause.label,
                                style: AppTextStyles.body.copyWith(fontSize: 14),
                              ),
                              value: _selectedCauses.contains(cause.id),
                              activeColor: AppColors.navy,
                              onChanged: _submitting
                                  ? null
                                  : (checked) => setState(() {
                                        if (checked == true) {
                                          _selectedCauses.add(cause.id);
                                        } else {
                                          _selectedCauses.remove(cause.id);
                                        }
                                      }),
                            ),
                          ),
                        ),
                      ],
                      if (_flow == _DeceasedFlow.freeText ||
                          _typeId == DeceasedReason.deathTypeOther) ...[
                        const SizedBox(height: AppSpacing.xxxl),
                        EnrollmentInputField(
                          label: MemberDeceasedStrings.reason,
                          hint: MemberDeceasedStrings.reasonHint,
                          controller: _reasonController,
                          isRequired: true,
                          maxLines: 3,
                          minLines: 3,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.h5xl),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.navy.withValues(alpha: 0.35),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(MemberDeceasedStrings.submit),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 44,
                child: TextButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    minimumSize: const Size.fromHeight(44),
                    textStyle: const TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(EnrollmentStrings.cancel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
