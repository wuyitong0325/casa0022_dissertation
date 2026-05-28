import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import 'species_repository.dart';

class OnlineSpeciesService {
  final Map<String, SpeciesProfile> _profileCache = {};
  final Map<String, _AudioResult?> _audioCache = {};

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
        ? await fetchBirdAudio(
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

  Future<_AudioResult?> fetchBirdAudio({
    required String commonName,
    required String scientificName,
  }) async {
    final cacheKey =
        '${commonName.toLowerCase().trim()}|${scientificName.toLowerCase().trim()}';

    if (_audioCache.containsKey(cacheKey)) {
      return _audioCache[cacheKey];
    }

    final queries = <String>[
      // 最靠谱：学名 + 质量优先
      if (_clean(scientificName).isNotEmpty) '${_clean(scientificName)} q:A',
      if (_clean(scientificName).isNotEmpty) '${_clean(scientificName)} q:B',
      if (_clean(scientificName).isNotEmpty) _clean(scientificName),

      // 备用：common name
      if (_clean(commonName).isNotEmpty) '${_clean(commonName)} q:A',
      if (_clean(commonName).isNotEmpty) '${_clean(commonName)} q:B',
      if (_clean(commonName).isNotEmpty) _clean(commonName),
    ];

    for (final query in queries) {
      final result = await _tryXenoCantoQuery(query);
      if (result != null) {
        _audioCache[cacheKey] = result;
        return result;
      }
    }

    _audioCache[cacheKey] = null;
    return null;
  }

  Future<_AudioResult?> _tryXenoCantoQuery(String queryText) async {
    final encoded = Uri.encodeQueryComponent(queryText);

    final endpoints = [
      // 新版 API
      'https://xeno-canto.org/api/3/recordings?query=$encoded',

      // 旧版备用
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

        final candidates = recordings
            .whereType<Map<String, dynamic>>()
            .where(_isPlayableCandidate)
            .toList()
          ..sort((a, b) => _candidateScore(b).compareTo(_candidateScore(a)));

        for (final item in candidates) {
          final audioUrl = _resolveXenoCantoAudioUrl(item);
          if (audioUrl == null) continue;

          final id = item['id']?.toString();
          final englishName = item['en']?.toString();
          final scientificName = item['gen'] != null && item['sp'] != null
              ? '${item['gen']} ${item['sp']}'
              : null;
          final recordist = item['rec']?.toString();
          final quality = item['q']?.toString();
          final country = item['cnt']?.toString();

          return _AudioResult(
            audioUrl: audioUrl,
            sourceLabel: [
              'xeno-canto',
              if (quality != null && quality.isNotEmpty) 'quality $quality',
              if (recordist != null && recordist.isNotEmpty) 'recordist $recordist',
            ].join(' · '),
            sourcePageUrl:
                id == null || id.isEmpty ? 'https://xeno-canto.org' : 'https://xeno-canto.org/$id',
            displayTitle: [
              if (englishName != null && englishName.isNotEmpty) englishName,
              if (scientificName != null && scientificName.trim().isNotEmpty)
                scientificName,
              if (country != null && country.isNotEmpty) country,
            ].join(' · '),
          );
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  bool _isPlayableCandidate(Map<String, dynamic> item) {
    final id = item['id']?.toString();
    final file = item['file']?.toString();

    // 有些受限制录音没有可下载/播放文件，FAQ 里也说明部分 recording 可能禁止 streaming/download。
    // 所以必须过滤：没有 file 也没有 id 的，不播。
    if ((id == null || id.isEmpty) && (file == null || file.isEmpty)) {
      return false;
    }

    final quality = item['q']?.toString().toUpperCase();
    if (quality == 'E') return false;

    return true;
  }

  int _candidateScore(Map<String, dynamic> item) {
    int score = 0;

    score += _qualityScore(item['q']?.toString()) * 100;

    final type = item['type']?.toString().toLowerCase() ?? '';
    if (type.contains('song')) score += 25;
    if (type.contains('call')) score += 20;

    final length = item['length']?.toString();
    final seconds = _lengthToSeconds(length);
    if (seconds != null) {
      if (seconds >= 2 && seconds <= 60) score += 25;
      if (seconds > 120) score -= 20;
    }

    final file = item['file']?.toString() ?? '';
    if (file.contains('xeno-canto.org')) score += 15;

    return score;
  }

  String? _resolveXenoCantoAudioUrl(Map<String, dynamic> item) {
    final file = item['file']?.toString().trim();
    final id = item['id']?.toString().trim();

    final normalised = _normaliseUrl(file);
    if (normalised != null) return normalised;

    if (id != null && id.isNotEmpty) {
      return 'https://xeno-canto.org/$id/download';
    }

    return null;
  }

  String? _normaliseUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final value = raw.trim();

    if (value.startsWith('https://')) return value;
    if (value.startsWith('http://')) return value;
    if (value.startsWith('//')) return 'https:$value';

    return null;
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
  final String displayTitle;

  const _AudioResult({
    required this.audioUrl,
    required this.sourceLabel,
    required this.sourcePageUrl,
    required this.displayTitle,
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