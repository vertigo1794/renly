// app/lib/core/location/location_capture.dart
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

import '../constants/malaysian_states.dart';

/// Result of a successful "Use my current location" capture on Post
/// Listing/Post Requirement. [area]/[matchedState] are best-effort
/// reverse-geocode results -- either can be null if geocoding failed or
/// returned nothing usable; [latitude]/[longitude] are always real GPS
/// values whenever this class exists at all.
class CapturedLocation {
  const CapturedLocation({required this.latitude, required this.longitude, this.area, this.matchedState});

  final double latitude;
  final double longitude;
  final String? area;
  final String? matchedState;
}

/// Requests location permission, captures the device's current GPS
/// position via Geolocator, and reverse-geocodes it into an area/state
/// guess via the `geocoding` package. Returns null on permission denial,
/// disabled location services, or any failure along the way -- the
/// caller shows its own error message; this never throws.
Future<CapturedLocation?> captureCurrentLocation() async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return null;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return null;
    }

    // A bounded timeLimit is required here -- without one, a slow/absent GPS
    // fix (common on emulators with no real GPS hardware) leaves the button
    // spinning forever with no way for the user to know it failed.
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 12)),
    );

    String? area;
    String? matchedState;
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        area = (placemark.subAdministrativeArea?.isNotEmpty ?? false)
            ? placemark.subAdministrativeArea
            : placemark.locality;
        matchedState = _matchMalaysianState(placemark.administrativeArea);
      }
    } catch (_) {
      // Reverse geocoding is best-effort -- coordinates alone are still
      // useful even if this fails (e.g. no network for the geocoding API).
    }

    return CapturedLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      area: area,
      matchedState: matchedState,
    );
  } catch (_) {
    return null;
  }
}

/// `geocoding`'s administrativeArea string doesn't always match this
/// app's fixed [malaysianStates] list exactly (e.g. "Kuala Lumpur" vs
/// "W.P. Kuala Lumpur", "Penang" vs "Pulau Pinang") -- try an exact match
/// first, then a loose substring match in both directions before giving
/// up and returning null (caller keeps whatever state was already
/// selected rather than clearing it).
String? _matchMalaysianState(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final state in malaysianStates) {
    if (state.toLowerCase() == raw.toLowerCase()) return state;
  }
  for (final state in malaysianStates) {
    final normalizedState = state.toLowerCase().replaceAll('w.p. ', '');
    final normalizedRaw = raw.toLowerCase();
    if (normalizedState.contains(normalizedRaw) || normalizedRaw.contains(normalizedState)) {
      return state;
    }
  }
  return null;
}
