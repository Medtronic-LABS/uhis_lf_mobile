import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/core/sync/sync_progress.dart';

/// Sync text must follow a mid-sync language switch.
///
/// The failure this guards against: `OfflineSyncService` is an app-level
/// singleton provided *above* the language-keyed `MaterialApp`, so the
/// `SyncProgress` object it holds survives the remount that a language change
/// triggers. Anything localized at emit time stays frozen in the old language
/// — which is why the sync screen kept showing English after switching to
/// Bangla. Emitters therefore pass data; the UI localizes at build.
void main() {
  // Without the real bundle every getter returns its English fallback, and the
  // language assertion below would pass vacuously.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTranslations();
  });

  tearDown(() => AppLocale.current = AppLanguage.english);

  test('step labels follow the current language, not the emit-time one', () {
    const progress = SyncProgress(currentStep: SyncStep.fetchingPatients);

    AppLocale.current = AppLanguage.english;
    final english = progress.currentStep.label;

    // Same object, language switched afterwards — as happens mid-sync.
    AppLocale.current = AppLanguage.bangla;
    final bangla = progress.currentStep.label;

    expect(english, isNotEmpty);
    expect(bangla, isNotEmpty);
    expect(
      bangla,
      isNot(english),
      reason: 'the label is read at build time, so it must change with the '
          'language even for a progress object emitted earlier',
    );
  });

  test('retry state is carried as numbers, not a rendered message', () {
    const progress = SyncProgress(
      currentStep: SyncStep.fetchingPatients,
      retryAttempt: 2,
      retryMaxAttempts: 3,
    );

    expect(progress.isRetrying, isTrue);
    expect(progress.retryAttempt, 2);
    expect(progress.retryMaxAttempts, 3);
    // Nothing human-readable is stored: the UI formats these at build time.
    expect(progress.entityName, isEmpty);
  });

  test('a non-retrying progress reports isRetrying false', () {
    const progress = SyncProgress(currentStep: SyncStep.processingData);
    expect(progress.isRetrying, isFalse);
  });

  test('copyWith preserves retry data', () {
    const progress = SyncProgress(retryAttempt: 1, retryMaxAttempts: 3);
    final copy = progress.copyWith(currentStep: SyncStep.processingData);
    expect(copy.retryAttempt, 1);
    expect(copy.retryMaxAttempts, 3);
  });
}
