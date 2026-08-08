import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/core/models/mission_brief.dart';

/// Locks the English wording for the shared filter-chip Semantics template,
/// [DayPriorityLevel.label], and [PerformanceStrings] weekday/week labels so
/// the Task 8 localization wiring cannot silently drift the rendered copy.
void main() {
  setUp(() {
    AppLocale.current = AppLanguage.english;
  });

  // AppLocale.current is a global static flag shared across the whole test
  // process (default is bangla) — restore english so this file never leaks
  // a different locale into unrelated test files run in the same suite.
  tearDown(() {
    AppLocale.current = AppLanguage.english;
  });

  group('MissionDashboardStrings filter-chip template', () {
    test('filterBy renders the shared "Filter by {label}" text', () {
      expect(MissionDashboardStrings.filterBy('ANC'), 'Filter by ANC');
    });

    test('filterSelected renders the need-bubble selected text', () {
      expect(
          MissionDashboardStrings.filterSelected('ANC'), 'ANC filter, selected');
    });

    test('filterUnavailable renders the disabled-chip text', () {
      expect(MissionDashboardStrings.filterUnavailable('ANC'),
          'ANC filter, unavailable');
    });

    test(
        'removeFilter renders the tier-chip selected text — distinct from '
        'filterSelected', () {
      expect(MissionDashboardStrings.removeFilter('ANC'), 'Remove filter: ANC');
      expect(MissionDashboardStrings.removeFilter('ANC'),
          isNot(MissionDashboardStrings.filterSelected('ANC')));
    });
  });

  group('DayPriorityLevel.label', () {
    test('returns the exact English label for every level', () {
      expect(DayPriorityLevel.critical.label, 'Critical');
      expect(DayPriorityLevel.high.label, 'High');
      expect(DayPriorityLevel.medium.label, 'Medium');
      expect(DayPriorityLevel.low.label, 'Low');
    });
  });

  group('PerformanceStrings.weekdayLabels', () {
    test('returns the exact 7-entry list, including duplicate letters', () {
      expect(PerformanceStrings.weekdayLabels,
          ['M', 'T', 'W', 'T', 'F', 'S', 'S']);
    });
  });

  group('PerformanceStrings.weekLabels', () {
    test('returns the exact 4-entry list', () {
      expect(PerformanceStrings.weekLabels, ['W1', 'W2', 'W3', 'W4']);
    });
  });

  group('Additional Task 8 getters', () {
    test('daysOverdueSuffix renders "+{n}d"', () {
      expect(MissionDashboardStrings.daysOverdueSuffix(3), '+3d');
    });

    test('moreAlerts pluralises correctly', () {
      expect(MissionDashboardStrings.moreAlerts(1), '+1 more alert');
      expect(MissionDashboardStrings.moreAlerts(2), '+2 more alerts');
    });

    test('todaysProgressHeader renders the mission-progress-card header', () {
      expect(MissionDashboardStrings.todaysProgressHeader('7 Aug'),
          "Today's Progress · 7 Aug");
    });

    test('todaysProgressHeader is distinct from aiBriefTodayHeader', () {
      expect(MissionDashboardStrings.todaysProgressHeader('7 Aug'),
          isNot(MissionDashboardStrings.aiBriefTodayHeader('7 Aug')));
    });

    test('searchResultsNotInQueue renders the global-search caption', () {
      expect(MissionDashboardStrings.searchResultsNotInQueue,
          "Search results — not in today's queue");
    });

    test('genderLabel normalises known values and passes through unknown ones',
        () {
      expect(MissionDashboardStrings.genderLabel('Male'), 'Male');
      expect(MissionDashboardStrings.genderLabel('female'), 'Female');
      expect(MissionDashboardStrings.genderLabel('F'), 'Female');
      expect(MissionDashboardStrings.genderLabel('Unspecified'), 'Unspecified');
    });
  });
}
