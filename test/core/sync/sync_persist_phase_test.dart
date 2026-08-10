import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/core/sync/sync_progress.dart';

/// The persist phase is what makes the processing bar honest: it runs 45-66 s
/// on a Pixel 10a, and every phase has a row count known before it starts.
void main() {
  setUpAll(() async {
    // Without the real bundle every getter returns its English fallback and the
    // language assertion below would pass vacuously.
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTranslations();
  });

  tearDown(() => AppLocale.current = AppLanguage.english);

  test('every phase has a non-empty label in both languages', () {
    for (final phase in SyncPersistPhase.values) {
      AppLocale.current = AppLanguage.english;
      expect(phase.label, isNotEmpty, reason: '${phase.name} has no English');
      AppLocale.current = AppLanguage.bangla;
      expect(phase.label, isNotEmpty, reason: '${phase.name} has no Bangla');
    }
  });

  test('labels are resolved at build time, so a language switch is followed',
      () {
    const progress = SyncProgress(
      currentStep: SyncStep.processingData,
      persistPhase: SyncPersistPhase.members,
    );

    AppLocale.current = AppLanguage.english;
    final english = progress.persistPhase!.label;
    // Same object, language switched afterwards — as happens mid-sync.
    AppLocale.current = AppLanguage.bangla;
    final bangla = progress.persistPhase!.label;

    expect(bangla, isNot(english));
  });

  test('every phase is distinctly labelled — no two read the same', () {
    final labels = SyncPersistPhase.values.map((p) => p.label).toList();
    expect(labels.toSet().length, labels.length,
        reason: 'duplicate labels would make the bar look stuck');
  });

  test('progress carries counts, and copyWith preserves the phase', () {
    const progress = SyncProgress(
      currentStep: SyncStep.processingData,
      persistPhase: SyncPersistPhase.members,
      itemsDone: 2400,
      itemsTotal: 3566,
    );

    expect(progress.itemsTotal, greaterThan(0),
        reason: 'a determinate bar needs a known total');
    final copy = progress.copyWith(itemsDone: 3000);
    expect(copy.persistPhase, SyncPersistPhase.members);
    expect(copy.itemsTotal, 3566);
  });

  test('a progress without a persist phase leaves it null', () {
    // The server fetch is genuinely unpredictable and must stay indeterminate —
    // a fake bar there would train SKs to distrust the real one.
    const fetching = SyncProgress(currentStep: SyncStep.fetchingPatients);
    expect(fetching.persistPhase, isNull);
    expect(fetching.itemsTotal, 0);
  });
}
