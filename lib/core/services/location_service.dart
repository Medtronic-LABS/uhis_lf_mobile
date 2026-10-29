import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Wraps device GPS for household/member enrollment and assessments.
///
/// Uses [permission_handler] for the runtime prompt (same plugin as onboarding),
/// then [Geolocator] for the fix — Geolocator-only requests are unreliable on
/// some Android builds when permission was never granted.
class LocationService {
  const LocationService._();

  /// Shows the system location permission dialog when still needed.
  ///
  /// Matches Spice `withLocationCheck` / `requestLocationPermissions` on member
  /// registration — call when the add-member screen opens or before save.
  static Future<bool> ensurePermission() async {
    if (kIsWeb) return false;

    try {
      var status = await Permission.locationWhenInUse.status;
      if (status.isGranted) return true;

      if (status.isDenied || status.isLimited) {
        status = await Permission.locationWhenInUse.request();
        if (status.isGranted) return true;
      }

      if (status.isPermanentlyDenied) {
        debugPrint('[LocationService] location permanently denied');
        return false;
      }

      // Fallback when permission_handler and Geolocator disagree on state.
      var geo = await Geolocator.checkPermission();
      if (geo == LocationPermission.denied) {
        geo = await Geolocator.requestPermission();
      }
      return geo == LocationPermission.whileInUse ||
          geo == LocationPermission.always;
    } catch (e) {
      debugPrint('[LocationService] ensurePermission failed: $e');
      return false;
    }
  }

  /// Returns the current GPS position, or (0.0, 0.0) on any failure.
  static Future<({double latitude, double longitude})> getCurrentPosition() async {
    try {
      if (!await ensurePermission()) return _zero;

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[LocationService] device location services disabled');
        return _zero;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return (latitude: position.latitude, longitude: position.longitude);
    } catch (e) {
      debugPrint('[LocationService] getCurrentPosition failed: $e');
      return _zero;
    }
  }

  static const _zero = (latitude: 0.0, longitude: 0.0);
}
