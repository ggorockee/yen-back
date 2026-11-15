import 'package:geolocator/geolocator.dart';

/// Result of asking for the device location.
enum LocationStatus { ok, denied, deniedForever, serviceOff, unavailable }

class LocationResult {
  const LocationResult(this.status, {this.lat, this.lng});
  final LocationStatus status;
  final double? lat;
  final double? lng;
  bool get ok => status == LocationStatus.ok;
}

/// Device location for "nearby branches". Asked only when the user opens the
/// shop form, never in the background, and sent only with a branch search.
abstract class LocationService {
  Future<LocationResult> current({bool request = true});
}

class DeviceLocationService implements LocationService {
  @override
  Future<LocationResult> current({bool request = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationStatus.serviceOff);
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && request) {
        perm = await Geolocator.requestPermission();
      }
      switch (perm) {
        case LocationPermission.denied:
          return const LocationResult(LocationStatus.denied);
        case LocationPermission.deniedForever:
          return const LocationResult(LocationStatus.deniedForever);
        case LocationPermission.whileInUse:
        case LocationPermission.always:
        case LocationPermission.unableToDetermine:
          break;
      }
      // A recent fix is good enough to rank branches and makes the list instant.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 10)) {
        return LocationResult(LocationStatus.ok, lat: last.latitude, lng: last.longitude);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 6)),
      );
      return LocationResult(LocationStatus.ok, lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return const LocationResult(LocationStatus.unavailable);
    }
  }

  /// Opens the OS settings so the user can grant a permanently denied permission.
  Future<void> openSettings() => Geolocator.openAppSettings();
}
