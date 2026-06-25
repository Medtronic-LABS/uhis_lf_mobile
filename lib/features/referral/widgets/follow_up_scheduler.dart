import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Dialog/sheet for scheduling a follow-up for a referral.
class FollowUpScheduler extends StatefulWidget {
  const FollowUpScheduler({
    super.key,
    required this.referralId,
    required this.patientName,
    this.existingFollowUpDate,
    required this.onSchedule,
  });

  final String referralId;
  final String patientName;
  final DateTime? existingFollowUpDate;
  final Future<bool> Function(DateTime date, String? type, String? notes) onSchedule;

  /// Show the follow-up scheduler as a dialog.
  static Future<bool?> show(
    BuildContext context, {
    required String referralId,
    required String patientName,
    DateTime? existingFollowUpDate,
    required Future<bool> Function(DateTime date, String? type, String? notes) onSchedule,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => FollowUpScheduler(
        referralId: referralId,
        patientName: patientName,
        existingFollowUpDate: existingFollowUpDate,
        onSchedule: onSchedule,
      ),
    );
  }

  @override
  State<FollowUpScheduler> createState() => _FollowUpSchedulerState();
}

class _FollowUpSchedulerState extends State<FollowUpScheduler> {
  late DateTime _selectedDate;
  TimeOfDay? _selectedTime;
  String? _selectedType;
  final _notesController = TextEditingController();
  bool _isLoading = false;

  final List<_FollowUpTypeOption> _typeOptions = const [
    _FollowUpTypeOption('check_up', 'Check-up', Icons.medical_services_outlined),
    _FollowUpTypeOption('medication', 'Medication Review', Icons.medication_outlined),
    _FollowUpTypeOption('lab_test', 'Lab Test', Icons.science_outlined),
    _FollowUpTypeOption('vitals', 'Vitals Check', Icons.monitor_heart_outlined),
    _FollowUpTypeOption('counseling', 'Counseling', Icons.psychology_outlined),
    _FollowUpTypeOption('other', 'Other', Icons.more_horiz_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.existingFollowUpDate ?? 
        DateTime.now().add(const Duration(days: 7));
    _selectedType = _typeOptions.first.id;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.event_rounded,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Schedule Follow-up',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.patientName,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Date picker
              _buildSectionTitle(context, 'Date'),
              const SizedBox(height: 8),
              Semantics(
                label: 'Select follow-up date: ${DateFormat.yMMMMEEEEd().format(_selectedDate)}',
                button: true,
                child: InkWell(
                onTap: _selectDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat.yMMMMEEEEd().format(_selectedDate),
                            style: textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _getRelativeDate(),
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.outline,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.outline,
                      ),
                    ],
                  ),
                ),
                ),
              ),
              const SizedBox(height: 16),

              // Quick date buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _QuickDateChip(
                    label: 'Tomorrow',
                    isSelected: _isDateEqual(
                      _selectedDate,
                      DateTime.now().add(const Duration(days: 1)),
                    ),
                    onTap: () => _setQuickDate(1),
                  ),
                  _QuickDateChip(
                    label: '3 Days',
                    isSelected: _isDateEqual(
                      _selectedDate,
                      DateTime.now().add(const Duration(days: 3)),
                    ),
                    onTap: () => _setQuickDate(3),
                  ),
                  _QuickDateChip(
                    label: '1 Week',
                    isSelected: _isDateEqual(
                      _selectedDate,
                      DateTime.now().add(const Duration(days: 7)),
                    ),
                    onTap: () => _setQuickDate(7),
                  ),
                  _QuickDateChip(
                    label: '2 Weeks',
                    isSelected: _isDateEqual(
                      _selectedDate,
                      DateTime.now().add(const Duration(days: 14)),
                    ),
                    onTap: () => _setQuickDate(14),
                  ),
                  _QuickDateChip(
                    label: '1 Month',
                    isSelected: _isDateEqual(
                      _selectedDate,
                      DateTime.now().add(const Duration(days: 30)),
                    ),
                    onTap: () => _setQuickDate(30),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Time picker (optional)
              _buildSectionTitle(context, 'Time (Optional)'),
              const SizedBox(height: 8),
              Semantics(
                label: _selectedTime != null
                    ? 'Follow-up time: ${_selectedTime!.format(context)}, tap to change'
                    : 'Add follow-up time',
                button: true,
                child: InkWell(
                onTap: _selectTime,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 20,
                        color: _selectedTime != null
                            ? scheme.primary
                            : scheme.outline,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _selectedTime != null
                            ? _selectedTime!.format(context)
                            : 'Add specific time',
                        style: textTheme.bodyMedium?.copyWith(
                          color: _selectedTime != null
                              ? null
                              : scheme.outline,
                        ),
                      ),
                      const Spacer(),
                      if (_selectedTime != null)
                        IconButton(
                          tooltip: 'Clear time',
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () =>
                              setState(() => _selectedTime = null),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                ),
              ),
              const SizedBox(height: 20),

              // Follow-up type
              _buildSectionTitle(context, 'Type'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in _typeOptions)
                    ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(type.icon, size: 16),
                          const SizedBox(width: 6),
                          Text(type.label),
                        ],
                      ),
                      selected: _selectedType == type.id,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedType = type.id);
                        }
                      },
                      selectedColor: scheme.primaryContainer,
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // Notes
              _buildSectionTitle(context, 'Notes (Optional)'),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Add any additional notes...',
                  filled: true,
                  fillColor: scheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isLoading ? null : _schedule,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Schedule'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  String _getRelativeDate() {
    final now = DateTime.now();
    final diff = _selectedDate.difference(now).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff < 7) return 'In $diff days';
    if (diff < 14) return 'In 1 week';
    if (diff < 30) return 'In ${(diff / 7).round()} weeks';
    return 'In ${(diff / 30).round()} month(s)';
  }

  bool _isDateEqual(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _setQuickDate(int days) {
    setState(() {
      _selectedDate = DateTime.now().add(Duration(days: days));
    });
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  Future<void> _schedule() async {
    setState(() => _isLoading = true);
    try {
      final scheduledDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime?.hour ?? 9,
        _selectedTime?.minute ?? 0,
      );

      final success = await widget.onSchedule(
        scheduledDateTime,
        _selectedType,
        _notesController.text.isEmpty ? null : _notesController.text,
      );

      if (mounted) {
        Navigator.pop(context, success);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

class _QuickDateChip extends StatelessWidget {
  const _QuickDateChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: isSelected ? 'Quick date: $label, selected' : 'Set follow-up to $label',
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? scheme.primaryContainer : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? scheme.onPrimaryContainer : scheme.onSurface,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowUpTypeOption {
  const _FollowUpTypeOption(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}
