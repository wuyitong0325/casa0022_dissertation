import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import 'species_repository.dart';

class OnlineSpeciesService {
  final Map<String, SpeciesProfile> _cache = {};

  Future<SpeciesProfile> fetchProfile(DetectionEvent event) async {
    final key = event.speciesKey;

    final cached = _cache[key];
    if (cached != null) return cached;

    final fallback = SpeciesRepository.findLocalProfile(event);

    String? summary;
    String? imageUrl;
    String? audioUrl;
    String? sourceUrl;

    final wiki = await _fetchWikipediaSummaryAndImage(
      event.commonName,
      event.scientificName,
    );

    if (wiki != null) {
      summary = wiki.description;
      imageUrl = wiki.imageUrl;
      sourceUrl = wiki.pageUrl;
    }

    if (event.isBird) {
      audioUrl = await _fetchXenoCantoAudio(
        commonName: event.commonName,
        scientificName: event.scientificName,
      );
    }

    final profile = fallback.copyWith(
      description: summary ?? fallback.description,
      imageUrl: imageUrl,
      audioUrl: audioUrl,
      sourceLabel:
          summary != null || audioUrl != null ? 'Online species data' : 'Local fallback',
      sourceUrl: sourceUrl,
      isOnline: summary != null || imageUrl != null || audioUrl != null,
    );

    _cache[key] = profile;
    return profile;
  }

  Future<_WikiResult?> _fetchWikipediaSummaryAndImage(
    String commonName,
    String scientificName,
  ) async {
    final candidates = <String>[
      commonName,
      scientificName,
    ].where((item) => item.trim().isNotEmpty && item.toLowerCase() != 'unknown');

    for (final name in candidates) {
      try {
        final title = Uri.encodeComponent(name.replaceAll(' ', '_'));

        final uri = Uri.parse(
          'https://en.wikipedia.org/api/rest_v1/page/summary/$title',
        );

        final response = await http.get(uri).timeout(
              const Duration(seconds: 8),
            );

        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        final description = data['extract']?.toString();
        final pageUrl = data['content_urls']?['desktop']?['page']?.toString();
        final imageUrl = data['thumbnail']?['source']?.toString();

        if (description == null || description.isEmpty) continue;

        return _WikiResult(
          description: description,
          imageUrl: imageUrl,
          pageUrl: pageUrl,
        );
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  Future<String?> _fetchXenoCantoAudio({
    required String commonName,
    required String scientificName,
  }) async {
    final queries = <String>[
      scientificName,
      commonName,
    ].where((item) => item.trim().isNotEmpty && item.toLowerCase() != 'unknown');

    for (final queryText in queries) {
      try {
        final query = Uri.encodeQueryComponent(queryText);

        final uri = Uri.parse(
          'https://xeno-canto.org/api/3/recordings?query=$query',
        );

        final response = await http.get(uri).timeout(
              const Duration(seconds: 8),
            );

        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        final recordings = data['recordings'];

        if (recordings is! List || recordings.isEmpty) continue;

        for (final item in recordings) {
          if (item is! Map<String, dynamic>) continue;

          final file = item['file']?.toString();

          if (file == null || file.isEmpty) continue;

          if (file.startsWith('http')) return file;
          if (file.startsWith('//')) return 'https:$file';
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }
}

class _WikiResult {
  final String description;
  final String? imageUrl;
  final String? pageUrl;

  _WikiResult({
    required this.description,
    this.imageUrl,
    this.pageUrl,
  });
}