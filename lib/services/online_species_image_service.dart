import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OnlineSpeciesImageResult {
  final String? imageUrl;
  final String? description;
  final String? sourceUrl;

  const OnlineSpeciesImageResult({
    required this.imageUrl,
    required this.description,
    required this.sourceUrl,
  });
}

class OnlineSpeciesImageService {
  Future<OnlineSpeciesImageResult?> fetchImageAndSummary({
    required String commonName,
    required String scientificName,
  }) async {
    final titles = <String>[
      scientificName.trim(),
      commonName.trim(),
    ].where((item) {
      return item.isNotEmpty &&
          item.toLowerCase() != 'unknown' &&
          !item.toLowerCase().contains('unknown');
    }).toList();

    for (final title in titles) {
      final result = await _fetchWikipediaSummary(title);

      if (result != null && result.imageUrl != null) {
        return result;
      }
    }

    for (final title in titles) {
      final result = await _fetchWikipediaSummary(title);

      if (result != null) {
        return result;
      }
    }

    return null;
  }

  Future<OnlineSpeciesImageResult?> _fetchWikipediaSummary(String title) async {
    try {
      final uri = Uri.parse(
        'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title)}',
      );

      debugPrint('Searching Wikipedia summary: $uri');

      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'ParkLifeMonitor/1.0',
          'Accept': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final thumbnail = decoded['thumbnail'];
      final contentUrls = decoded['content_urls'];

      String? imageUrl;

      if (thumbnail is Map<String, dynamic>) {
        imageUrl = thumbnail['source']?.toString();
      }

      String? pageUrl;

      if (contentUrls is Map<String, dynamic>) {
        final desktop = contentUrls['desktop'];

        if (desktop is Map<String, dynamic>) {
          pageUrl = desktop['page']?.toString();
        }
      }

      return OnlineSpeciesImageResult(
        imageUrl: imageUrl,
        description: decoded['extract']?.toString(),
        sourceUrl: pageUrl,
      );
    } catch (e) {
      debugPrint('Wikipedia image lookup failed: $e');
      return null;
    }
  }
}