import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

import '../config/app_config.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (canCheck) return true;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({String? reason}) async {
    final localizedReason = reason ?? AppConfig.biometricReason;
    try {
      return await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'UHIS Next',
            biometricHint: 'Verify your identity',
            cancelButton: 'Use password',
          ),
        ],
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
