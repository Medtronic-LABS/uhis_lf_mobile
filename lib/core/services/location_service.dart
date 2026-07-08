import 'package:geolocator/geolocator.dart';

/// Wraps [Geolocator] to fetch the device's current GPS position.
///
/// Used during household/member enrollment to stamp lat/lng on the payload,
/// matching the Android SPICE app's FusedLocationProviderClient behaviour.
/// Falls back to (0.0, 0.0) gracefully when location is unavailable or denied.
class LocationService {
  const LocationService._();

  /// Returns the current GPS position, or (0.0, 0.0) on any failure.
  ///
  /// Requests permission if not yet granted. Uses [LocationAccuracy.high]
  /// (GPS-grade) to match the Android reference payload precision.
  static Future<({double latitude, double longitude})> getCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return _zero;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _zero;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return (latitude: position.latitude, longitude: position.longitude);
    } catch (_) {
      return _zero;
    }
  }

  static const _zero = (latitude: 0.0, longitude: 0.0);
}
