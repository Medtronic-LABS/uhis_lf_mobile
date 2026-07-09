import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth_android/local_auth_android.dart';

import '../config/app_config.dart';
import '../constants/app_strings.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Returns true if the device has ANY lock set up (fingerprint, face, PIN,
  /// pattern, or password). Since we use `biometricOnly: false`, any of these
  /// methods will work for device unlock.
  Future<bool> isAvailable() async {
    try {
      // Check if device supports any authentication method
      final isSupported = await _auth.isDeviceSupported();
      if (!isSupported) {
        debugPrint('[BiometricService] Device does not support authentication');
        return false;
      }
      
      // Check if any credentials are enrolled (biometric OR device credentials)
      // canCheckBiometrics returns true only if biometrics are enrolled
      final canCheckBio = await _auth.canCheckBiometrics;
      final biometrics = await _auth.getAvailableBiometrics();
      
      debugPrint('[BiometricService] isDeviceSupported: $isSupported, canCheckBiometrics: $canCheckBio, biometrics: $biometrics');
      
      // Return true if either biometrics are available OR device has screen lock
      // (isDeviceSupported returns true if any authentication is available)
      return isSupported;
    } catch (e) {
      debugPrint('[BiometricService] isAvailable error: $e');
      return false;
    }
  }

  /// Check if the device has biometrics enrolled (fingerprint, face, etc.)
  Future<bool> hasBiometricsEnrolled() async {
    try {
      final biometrics = await _auth.getAvailableBiometrics();
      debugPrint('[BiometricService] Available biometrics: $biometrics');
      return biometrics.isNotEmpty;
    } catch (e) {
      debugPrint('[BiometricService] hasBiometricsEnrolled error: $e');
      return false;
    }
  }

  Future<bool> authenticate({String? reason}) async {
    final localizedReason = reason ?? AppConfig.biometricReason;
    try {
      debugPrint('[BiometricService] Starting authentication...');
      final result = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          // biometricOnly: false allows both biometrics (fingerprint/face) AND
          // device credentials (PIN/pattern/password). The Android system shows
          // whatever the user has set up. This is separate from the app's own
          // 4-digit PIN which has its own /pin-unlock screen.
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: BiometricStrings.promptTitle,
            cancelButton: BiometricStrings.cancelButton,
          ),
        ],
      );
      debugPrint('[BiometricService] Authentication result: $result');
      return result;
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] PlatformException: ${e.code} - ${e.message}');
      // Handle specific error codes
      if (e.code == auth_error.notEnrolled) {
        debugPrint('[BiometricService] No biometrics enrolled');
      } else if (e.code == auth_error.lockedOut) {
        debugPrint('[BiometricService] Too many attempts, locked out');
      } else if (e.code == auth_error.permanentlyLockedOut) {
        debugPrint('[BiometricService] Permanently locked out');
      } else if (e.code == auth_error.notAvailable) {
        debugPrint('[BiometricService] Biometric not available');
      }
      return false;
    } catch (e) {
      debugPrint('[BiometricService] Unexpected error: $e');
      return false;
    }
  }
}
