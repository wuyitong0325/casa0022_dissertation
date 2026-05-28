import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import 'species_repository.dart';

class OnlineSpeciesService {
  final Map<String, SpeciesProfile> _profileCache = {};

  Future<SpeciesProfile> fetchProfile(DetectionEvent event) async {
    final cached = _profileCache[event.speciesKey];
    if (cached != null) return cached;

    final local = SpeciesRepository.findLocalProfile(event);

    String? description;
    String? imageUrl;
    String? speciesSourceUrl;

    final wiki = await _fetchWikipediaSummaryAndImage(
      commonName: event.commonName,
      scientificName: event.scientificName,
    );

    if (wiki != null) {
      description = wiki.description;
      imageUrl = wiki.imageUrl;
      speciesSourceUrl = wiki.pageUrl;
    }

    final audio = event.isBird
        ? _knownBirdAudioByName[event.scientificName.toLowerCase().trim()] ??
            _knownBirdAudioByName[event.commonName.toLowerCase().trim()] ??
            await _fetchXenoCantoAudio(
              commonName: event.commonName,
              scientificName: event.scientificName,
            )
        : null;

    final profile = local.copyWith(
      description: description ?? local.description,
      imageUrl: imageUrl ?? local.imageUrl,
      sourceLabel: wiki == null ? local.sourceLabel : 'Wikipedia species summary',
      sourceUrl: speciesSourceUrl ?? local.sourceUrl,
      audioUrl: audio?.audioUrl,
      audioSourceLabel: audio?.sourceLabel,
      audioSourceUrl: audio?.sourcePageUrl,
      isOnline: wiki != null || audio != null,
    );

    _profileCache[event.speciesKey] = profile;
    return profile;
  }

  Future<_AudioResult?> _fetchXenoCantoAudio({
    required String commonName,
    required String scientificName,
  }) async {
    final cleanScientific = _clean(scientificName);
    final cleanCommon = _clean(commonName);

    final queries = <String>[
      if (cleanScientific.isNotEmpty) '$cleanScientific q:A',
      if (cleanScientific.isNotEmpty) '$cleanScientific q:B',
      if (cleanScientific.isNotEmpty) cleanScientific,
      if (cleanCommon.isNotEmpty) '$cleanCommon q:A',
      if (cleanCommon.isNotEmpty) '$cleanCommon q:B',
      if (cleanCommon.isNotEmpty) cleanCommon,
    ];

    for (final query in queries) {
      final result = await _tryXenoCantoQuery(query);
      if (result != null) return result;
    }

    return null;
  }

  Future<_AudioResult?> _tryXenoCantoQuery(String queryText) async {
    final encoded = Uri.encodeQueryComponent(queryText);

    final endpoints = [
      'https://xeno-canto.org/api/3/recordings?query=$encoded',
      'https://xeno-canto.org/api/2/recordings?query=$encoded',
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await http.get(
          Uri.parse(endpoint),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'ParkLifeMonitor/1.0',
          },
        ).timeout(const Duration(seconds: 12));

        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final recordings = data['recordings'];

        if (recordings is! List || recordings.isEmpty) continue;

        final candidates = recordings.whereType<Map<String, dynamic>>().toList()
          ..sort((a, b) => _candidateScore(b).compareTo(_candidateScore(a)));

        for (final item in candidates) {
          final id = item['id']?.toString();
          if (id == null || id.isEmpty) continue;

          final url = 'https://xeno-canto.org/$id/download';

          return _AudioResult(
            audioUrl: url,
            sourceLabel: _sourceLabelFromXenoItem(item),
            sourcePageUrl: 'https://xeno-canto.org/$id',
          );
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  String _sourceLabelFromXenoItem(Map<String, dynamic> item) {
    final quality = item['q']?.toString();
    final recordist = item['rec']?.toString();
    final country = item['cnt']?.toString();

    final parts = [
      'xeno-canto real recording',
      if (quality != null && quality.isNotEmpty) 'quality $quality',
      if (country != null && country.isNotEmpty) country,
      if (recordist != null && recordist.isNotEmpty) 'by $recordist',
    ];

    return parts.join(' · ');
  }

  int _candidateScore(Map<String, dynamic> item) {
    int score = 0;

    score += _qualityScore(item['q']?.toString()) * 100;

    final type = item['type']?.toString().toLowerCase() ?? '';
    if (type.contains('song')) score += 30;
    if (type.contains('call')) score += 20;

    final length = item['length']?.toString();
    final seconds = _lengthToSeconds(length);

    if (seconds != null) {
      if (seconds >= 2 && seconds <= 90) score += 25;
      if (seconds > 180) score -= 25;
    }

    return score;
  }

  int _qualityScore(String? quality) {
    switch (quality?.toUpperCase()) {
      case 'A':
        return 5;
      case 'B':
        return 4;
      case 'C':
        return 3;
      case 'D':
        return 2;
      default:
        return 1;
    }
  }

  int? _lengthToSeconds(String? value) {
    if (value == null || value.trim().isEmpty) return null;

    final parts = value.split(':');
    if (parts.length != 2) return null;

    final minutes = int.tryParse(parts[0]);
    final seconds = int.tryParse(parts[1]);

    if (minutes == null || seconds == null) return null;

    return minutes * 60 + seconds;
  }

  String _clean(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) return '';
    if (trimmed.toLowerCase() == 'unknown') return '';
    if (trimmed.toLowerCase().contains('possible')) return '';

    return trimmed;
  }

  Future<_WikiResult?> _fetchWikipediaSummaryAndImage({
    required String commonName,
    required String scientificName,
  }) async {
    final candidates = [
      commonName,
      scientificName,
    ].where((item) => _clean(item).isNotEmpty);

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

        final originalImage = data['originalimage'];
        final thumb = data['thumbnail'];

        final imageUrl = originalImage is Map<String, dynamic>
            ? originalImage['source']?.toString()
            : thumb is Map<String, dynamic>
                ? thumb['source']?.toString()
                : null;

        if (description == null || description.trim().isEmpty) continue;

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
}

class _AudioResult {
  final String audioUrl;
  final String sourceLabel;
  final String sourcePageUrl;

  const _AudioResult({
    required this.audioUrl,
    required this.sourceLabel,
    required this.sourcePageUrl,
  });
}

class _WikiResult {
  final String description;
  final String? imageUrl;
  final String? pageUrl;

  const _WikiResult({
    required this.description,
    this.imageUrl,
    this.pageUrl,
  });
}

// 先保证 Sound Lab 里这些常见鸟必定有真实 xeno-canto 链接。
// 这些 URL 都是 xeno-canto download endpoint，是真实 recording，不是合成声音。
const Map<String, _AudioResult> _knownBirdAudioByName = {
  'turdus merula': _AudioResult(
    audioUrl: 'https://xeno-canto.org/739319/download',
    sourceLabel: 'xeno-canto real recording · Common Blackbird',
    sourcePageUrl: 'https://xeno-canto.org/739319',
  ),
  'common blackbird': _AudioResult(
    audioUrl: 'https://xeno-canto.org/739319/download',
    sourceLabel: 'xeno-canto real recording · Common Blackbird',
    sourcePageUrl: 'https://xeno-canto.org/739319',
  ),

  'erithacus rubecula': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744846/download',
    sourceLabel: 'xeno-canto real recording · European Robin',
    sourcePageUrl: 'https://xeno-canto.org/744846',
  ),
  'european robin': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744846/download',
    sourceLabel: 'xeno-canto real recording · European Robin',
    sourcePageUrl: 'https://xeno-canto.org/744846',
  ),

  'parus major': _AudioResult(
    audioUrl: 'https://xeno-canto.org/745170/download',
    sourceLabel: 'xeno-canto real recording · Great Tit',
    sourcePageUrl: 'https://xeno-canto.org/745170',
  ),
  'great tit': _AudioResult(
    audioUrl: 'https://xeno-canto.org/745170/download',
    sourceLabel: 'xeno-canto real recording · Great Tit',
    sourcePageUrl: 'https://xeno-canto.org/745170',
  ),

  'cyanistes caeruleus': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744820/download',
    sourceLabel: 'xeno-canto real recording · Blue Tit',
    sourcePageUrl: 'https://xeno-canto.org/744820',
  ),
  'blue tit': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744820/download',
    sourceLabel: 'xeno-canto real recording · Blue Tit',
    sourcePageUrl: 'https://xeno-canto.org/744820',
  ),

  'troglodytes troglodytes': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744942/download',
    sourceLabel: 'xeno-canto real recording · Eurasian Wren',
    sourcePageUrl: 'https://xeno-canto.org/744942',
  ),
  'eurasian wren': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744942/download',
    sourceLabel: 'xeno-canto real recording · Eurasian Wren',
    sourcePageUrl: 'https://xeno-canto.org/744942',
  ),

  'passer domesticus': _AudioResult(
    audioUrl: 'https://xeno-canto.org/742447/download',
    sourceLabel: 'xeno-canto real recording · House Sparrow',
    sourcePageUrl: 'https://xeno-canto.org/742447',
  ),
  'house sparrow': _AudioResult(
    audioUrl: 'https://xeno-canto.org/742447/download',
    sourceLabel: 'xeno-canto real recording · House Sparrow',
    sourcePageUrl: 'https://xeno-canto.org/742447',
  ),

  'columba palumbus': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744365/download',
    sourceLabel: 'xeno-canto real recording · Wood Pigeon',
    sourcePageUrl: 'https://xeno-canto.org/744365',
  ),
  'wood pigeon': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744365/download',
    sourceLabel: 'xeno-canto real recording · Wood Pigeon',
    sourcePageUrl: 'https://xeno-canto.org/744365',
  ),

  'corvus corone': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744914/download',
    sourceLabel: 'xeno-canto real recording · Carrion Crow',
    sourcePageUrl: 'https://xeno-canto.org/744914',
  ),
  'carrion crow': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744914/download',
    sourceLabel: 'xeno-canto real recording · Carrion Crow',
    sourcePageUrl: 'https://xeno-canto.org/744914',
  ),

  'pica pica': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744899/download',
    sourceLabel: 'xeno-canto real recording · Eurasian Magpie',
    sourcePageUrl: 'https://xeno-canto.org/744899',
  ),
  'eurasian magpie': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744899/download',
    sourceLabel: 'xeno-canto real recording · Eurasian Magpie',
    sourcePageUrl: 'https://xeno-canto.org/744899',
  ),

  'fringilla coelebs': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744833/download',
    sourceLabel: 'xeno-canto real recording · Common Chaffinch',
    sourcePageUrl: 'https://xeno-canto.org/744833',
  ),
  'common chaffinch': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744833/download',
    sourceLabel: 'xeno-canto real recording · Common Chaffinch',
    sourcePageUrl: 'https://xeno-canto.org/744833',
  ),

  'cuculus canorus': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744610/download',
    sourceLabel: 'xeno-canto real recording · Common Cuckoo',
    sourcePageUrl: 'https://xeno-canto.org/744610',
  ),
  'common cuckoo': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744610/download',
    sourceLabel: 'xeno-canto real recording · Common Cuckoo',
    sourcePageUrl: 'https://xeno-canto.org/744610',
  ),

  'corvus corax': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744905/download',
    sourceLabel: 'xeno-canto real recording · Common Raven',
    sourcePageUrl: 'https://xeno-canto.org/744905',
  ),
  'common raven': _AudioResult(
    audioUrl: 'https://xeno-canto.org/744905/download',
    sourceLabel: 'xeno-canto real recording · Common Raven',
    sourcePageUrl: 'https://xeno-canto.org/744905',
  ),
};