import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A place returned by a geocoding lookup.
class GeocodeResult {
  const GeocodeResult({required this.point, required this.displayName});
  final LatLng point;
  final String displayName;
}

class GeocodingException implements Exception {
  const GeocodingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Address lookup against OpenStreetMap's Nominatim service.
///
/// Nominatim's usage policy requires an identifying User-Agent and forbids
/// bulk or automatic querying, so this runs only from an explicit user action
/// and asks for a single result.
class Geocoder {
  const Geocoder({this.client});
  final http.Client? client;

  static const _endpoint = 'https://nominatim.openstreetmap.org/search';
  static const _userAgent = 'SoulServe/1.0 (org.soulserve.app)';

  Future<GeocodeResult> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) {
      throw const GeocodingException('Enter an address with at least 3 characters.');
    }
    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'q': trimmed,
      'format': 'jsonv2',
      'limit': '1',
      'addressdetails': '0',
    });

    final http.Response response;
    try {
      final agent = client ?? http.Client();
      try {
        response = await agent
            .get(uri, headers: const {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 12));
      } finally {
        if (client == null) agent.close();
      }
    } catch (_) {
      throw const GeocodingException(
          'Could not reach the address service. Check your connection.');
    }

    if (response.statusCode != 200) {
      throw const GeocodingException(
          'The address service is unavailable right now.');
    }

    final List<dynamic> results;
    try {
      results = jsonDecode(response.body) as List<dynamic>;
    } catch (_) {
      throw const GeocodingException('The address service sent an unexpected reply.');
    }
    if (results.isEmpty) {
      throw const GeocodingException(
          'No match for that address. Try adding a city or postcode.');
    }

    final first = Map<String, dynamic>.from(results.first as Map);
    final latitude = double.tryParse('${first['lat']}');
    final longitude = double.tryParse('${first['lon']}');
    if (latitude == null || longitude == null) {
      throw const GeocodingException('The address service sent an unexpected reply.');
    }
    return GeocodeResult(
      point: LatLng(latitude, longitude),
      displayName: '${first['display_name'] ?? trimmed}',
    );
  }
}
