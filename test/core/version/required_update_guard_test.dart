import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:uhis_next/core/version/play_update_client.dart';
import 'package:uhis_next/core/version/required_update_guard.dart';

PlayUpdateSnapshot _snap({
  UpdateAvailability availability = UpdateAvailability.updateAvailable,
  bool immediate = true,
  bool flexible = true,
  InstallStatus status = InstallStatus.unknown,
  int? offered = 20,
}) =>
    PlayUpdateSnapshot(
      availability: availability,
      immediateAllowed: immediate,
      flexibleAllowed: flexible,
      installStatus: status,
      availableVersionCode: offered,
    );

RequiredUpdateDecision _decide(PlayUpdateSnapshot? play,
        {int min = 10, bool graceExpired = false}) =>
    decideRequiredUpdate(
      play: play,
      minVersionCode: min,
      graceExpired: graceExpired,
    );

void main() {
  group('decideRequiredUpdate', () {
    test('Play offers a build at or above the minimum → block', () {
      expect(_decide(_snap(offered: 10)), RequiredUpdateDecision.blockWithUpdate);
      expect(_decide(_snap(offered: 20)), RequiredUpdateDecision.blockWithUpdate);
    });

    test('null offered version code is treated as deliverable', () {
      expect(_decide(_snap(offered: null)),
          RequiredUpdateDecision.blockWithUpdate);
    });

    test('Play offers a build below the minimum → warn, never block', () {
      expect(_decide(_snap(offered: 9)), RequiredUpdateDecision.warn);
    });

    test('Play offers nothing → warn', () {
      expect(
        _decide(_snap(availability: UpdateAvailability.updateNotAvailable)),
        RequiredUpdateDecision.warn,
      );
    });

    test('immediate not allowed → warn', () {
      expect(_decide(_snap(immediate: false)), RequiredUpdateDecision.warn);
    });

    test('Play unusable (null snapshot) → warn', () {
      expect(_decide(null), RequiredUpdateDecision.warn);
    });

    test('not deliverable after grace → stranded, still not a block', () {
      expect(_decide(null, graceExpired: true),
          RequiredUpdateDecision.warnStranded);
      expect(
        _decide(_snap(offered: 9), graceExpired: true),
        RequiredUpdateDecision.warnStranded,
      );
    });

    test('deliverable always blocks, even after grace', () {
      expect(_decide(_snap(), graceExpired: true),
          RequiredUpdateDecision.blockWithUpdate);
    });

    test('interrupted immediate update or downloaded flexible → block', () {
      expect(
        _decide(_snap(
          availability: UpdateAvailability.developerTriggeredUpdateInProgress,
          immediate: false,
        )),
        RequiredUpdateDecision.blockWithUpdate,
      );
      expect(
        _decide(_snap(
          availability: UpdateAvailability.updateNotAvailable,
          status: InstallStatus.downloaded,
        )),
        RequiredUpdateDecision.blockWithUpdate,
      );
    });
  });
}
