import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/core/sync/sync_progress.dart';

void main() {
  tearDown(() => AppLocale.current = AppLanguage.english);

  test('SyncStepX.label is byte-identical to the existing English text', () {
    AppLocale.current = AppLanguage.english;
    expect(SyncStep.connecting.label, 'Connecting to server');
    expect(SyncStep.fetchingPatients.label, 'Downloading patients');
    expect(SyncStep.fetchingFollowUps.label, 'Downloading follow-ups');
    expect(SyncStep.fetchingReferrals.label, 'Downloading referrals');
    expect(SyncStep.processingData.label, 'Processing data');
    expect(SyncStep.done.label, 'Ready');
  });
}
