import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/referral.dart';

/// Search and filter bar for referral list.
/// Provides text search, status filters, date range, and sort options.
class ReferralSearchFilterBar extends StatefulWidget {
  const ReferralSearchFilterBar({
    super.key,
    this.onSearchChanged,
    this.onStatusFilterChanged,
    this.onDateRangeChanged,
    this.onSortChanged,
    this.selectedStatuses = const {},
    this.selectedSort = ReferralSortOption.priorityDesc,
    this.dateRange,
    this.searchText = '',
  });

  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<Set<ReferralStatusFilter>>? onStatusFilterChanged;
  final ValueChanged<DateTimeRange?>? onDateRangeChanged;
  final ValueChanged<ReferralSortOption>? onSortChanged;
  final Set<ReferralStatusFilter> selectedStatuses;
  final ReferralSortOption selectedSort;
  final DateTimeRange? dateRange;
  final String searchText;

  @override
  State<ReferralSearchFilterBar> createState() => _ReferralSearchFilterBarState();
}

class _ReferralSearchFilterBarState extends State<ReferralSearchFilterBar> {
  late final TextEditingController _searchController;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchText);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search bar row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search patients or conditions...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              widget.onSearchChanged?.call('');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: widget.onSearchChanged,
                ),
              ),
              const SizedBox(width: 8),
              // Filter toggle button
              Badge(
                isLabelVisible:
                    widget.selectedStatuses.isNotEmpty || widget.dateRange != null,
                label: Text(
                  '${widget.selectedStatuses.length + (widget.dateRange != null ? 1 : 0)}',
                ),
                child: IconButton.filledTonal(
                  icon: Icon(
                    _showFilters ? Icons.filter_list_off : Icons.filter_list,
                    size: 22,
                  ),
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                  tooltip: 'Toggle filters',
                ),
              ),
              const SizedBox(width: 4),
              // Sort button
              PopupMenuButton<ReferralSortOption>(
                icon: const Icon(Icons.sort, size: 22),
                tooltip: 'Sort options',
                initialValue: widget.selectedSort,
                onSelected: widget.onSortChanged,
                itemBuilder: (context) => [
                  for (final option in ReferralSortOption.values)
                    PopupMenuItem(
                      value: option,
                      child: Row(
                        children: [
                          if (option == widget.selectedSort)
                            Icon(Icons.check, size: 18, color: scheme.primary)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Text(option.label),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // Expandable filter chips
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState:
              _showFilters ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status filter chips
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final status in ReferralStatusFilter.values)
                      FilterChip(
                        label: Text(status.label),
                        avatar: Icon(
                          status.icon,
                          size: 16,
                          color: widget.selectedStatuses.contains(status)
                              ? scheme.onPrimaryContainer
                              : status.color,
                        ),
                        selected: widget.selectedStatuses.contains(status),
                        onSelected: (selected) {
                          final newSet = Set<ReferralStatusFilter>.from(
                              widget.selectedStatuses);
                          if (selected) {
                            newSet.add(status);
                          } else {
                            newSet.remove(status);
                          }
                          widget.onStatusFilterChanged?.call(newSet);
                        },
                        selectedColor: scheme.primaryContainer,
                        checkmarkColor: scheme.onPrimaryContainer,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // Date range picker
                Row(
                  children: [
                    Icon(Icons.date_range, size: 18, color: scheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        label: widget.dateRange != null
                            ? 'Date range filter: ${_formatDate(widget.dateRange!.start)} to ${_formatDate(widget.dateRange!.end)}'
                            : 'Filter by date range',
                        button: true,
                        child: InkWell(
                        onTap: () => _selectDateRange(context),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.dateRange != null
                                ? '${_formatDate(widget.dateRange!.start)} - ${_formatDate(widget.dateRange!.end)}'
                                : 'Filter by date range',
                            style: TextStyle(
                              color: widget.dateRange != null
                                  ? scheme.onSurface
                                  : scheme.outline,
                            ),
                          ),
                        ),
                        ),
                      ),
                    ),
                    if (widget.dateRange != null)
                      IconButton(
                        tooltip: 'Clear date filter',
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () =>
                            widget.onDateRangeChanged?.call(null),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
          secondChild: const SizedBox(height: 0),
        ),
      ],
    );
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      initialDateRange: widget.dateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            datePickerTheme: DatePickerThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (range != null) {
      widget.onDateRangeChanged?.call(range);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// Status filter options for referrals.
enum ReferralStatusFilter {
  overdue(
    'Overdue',
    Icons.warning_amber_rounded,
    AppColors.statusCritical,
  ),
  newReferral(
    'New',
    Icons.fiber_new_rounded,
    AppColors.statusInfo,
  ),
  inTreatment(
    'In Treatment',
    Icons.medical_services_rounded,
    AppColors.statusWarning,
  ),
  completed(
    'Completed',
    Icons.check_circle_rounded,
    AppColors.statusSuccess,
  ),
  escalated(
    'Escalated',
    Icons.trending_up_rounded,
    AppColors.aiPurple,
  );

  const ReferralStatusFilter(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  /// Check if a referral matches this filter.
  bool matches(Referral r) {
    switch (this) {
      case ReferralStatusFilter.overdue:
        return r.breachedSince != null;
      case ReferralStatusFilter.newReferral:
        return r.state == ReferralStatus.created ||
            r.state == ReferralStatus.acknowledged;
      case ReferralStatusFilter.inTreatment:
        return r.state == ReferralStatus.arrived ||
            r.state == ReferralStatus.treatmentStarted ||
            r.state == ReferralStatus.inTransit;
      case ReferralStatusFilter.completed:
        return r.state.isClosed;
      case ReferralStatusFilter.escalated:
        return r.escalationLevel > 0;
    }
  }
}

/// Sort options for referral list.
enum ReferralSortOption {
  priorityDesc('Priority (High to Low)'),
  priorityAsc('Priority (Low to High)'),
  dateDesc('Newest First'),
  dateAsc('Oldest First'),
  patientName('Patient Name'),
  urgency('Urgency Level');

  const ReferralSortOption(this.label);

  final String label;
}
