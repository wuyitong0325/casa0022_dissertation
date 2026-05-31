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
        ? await _resolveBirdAudio(
            commonName: event.commonName,
            scientificName: event.scientificName,
          )
        : await _resolveBatAudio(
            commonName: event.commonName,
            scientificName: event.scientificName,
          );

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

  Future<_AudioResult?> _resolveBirdAudio({
    required String commonName,
    required String scientificName,
  }) async {
    final key = 'bird:${_clean(commonName).toLowerCase()}|${_clean(scientificName).toLowerCase()}';
    if (_audioCache.containsKey(key)) return _audioCache[key];

    final known = _knownBirdAudioByName[_clean(scientificName).toLowerCase()] ??
        _knownBirdAudioByName[_clean(commonName).toLowerCase()];

    if (known != null) {
      _audioCache[key] = known;
      return known;
    }

    final api = await _fetchXenoCantoAudio(
      commonName: commonName,
      scientificName: scientificName,
      sourcePrefix: 'xeno-canto real bird recording',
    );

    _audioCache[key] = api;
    return api;
  }

  Future<_AudioResult?> _resolveBatAudio({
    required String commonName,
    required String scientificName,
  }) async {
    final key = 'bat:${_clean(commonName).toLowerCase()}|${_clean(scientificName).toLowerCase()}';
    if (_audioCache.containsKey(key)) return _audioCache[key];

    final cleanCommon = _normaliseName(commonName);
    final cleanScientific = _normaliseName(scientificName);

    final known = _knownBatAudioByName[cleanScientific] ??
        _knownBatAudioByName[cleanCommon];

    if (known != null) {
      _audioCache[key] = known;
      return known;
    }

    final gbif = await _fetchGbifSound(
      commonName: commonName,
      scientificName: scientificName,
      sourcePrefix: 'GBIF real bat sound',
    );
    if (gbif != null) {
      _audioCache[key] = gbif;
      return gbif;
    }

    final inat = await _fetchINaturalistSound(
      commonName: commonName,
      scientificName: scientificName,
      sourcePrefix: 'iNaturalist real bat sound',
    );
    if (inat != null) {
      _audioCache[key] = inat;
      return inat;
    }

    final xeno = await _fetchXenoCantoAudio(
      commonName: commonName,
      scientificName: scientificName,
      sourcePrefix: 'xeno-canto real bat recording',
    );

    _audioCache[key] = xeno;
    return xeno;
  }

  Future<_AudioResult?> _fetchXenoCantoAudio({
    required String commonName,
    required String scientificName,
    required String sourcePrefix,
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
      final result = await _tryXenoCantoQuery(query, sourcePrefix);
      if (result != null) return result;
    }

    return null;
  }

  Future<_AudioResult?> _tryXenoCantoQuery(
    String queryText,
    String sourcePrefix,
  ) async {
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
            sourceLabel: _sourceLabelFromXenoItem(item, sourcePrefix),
            sourcePageUrl: 'https://xeno-canto.org/$id',
          );
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  Future<_AudioResult?> _fetchGbifSound({
    required String commonName,
    required String scientificName,
    required String sourcePrefix,
  }) async {
    final queryName = _clean(scientificName).isNotEmpty
        ? _clean(scientificName)
        : _clean(commonName);

    if (queryName.isEmpty) return null;

    try {
      final uri = Uri.parse(
        'https://api.gbif.org/v1/occurrence/search'
        '?scientificName=${Uri.encodeQueryComponent(queryName)}'
        '&mediaType=Sound'
        '&limit=25',
      );

      final response = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'ParkLifeMonitor/1.0',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'];

      if (results is! List) return null;

      for (final result in results.whereType<Map<String, dynamic>>()) {
        final media = result['media'];
        if (media is! List) continue;

        for (final item in media.whereType<Map<String, dynamic>>()) {
          final type = item['type']?.toString().toLowerCase() ?? '';
          final identifier = item['identifier']?.toString();
          final references = item['references']?.toString();

          final candidate = _normaliseAudioUrl(identifier) ??
              _normaliseAudioUrl(references);

          if (candidate == null) continue;

          if (type.contains('sound') || _looksLikeAudioUrl(candidate)) {
            return _AudioResult(
              audioUrl: candidate,
              sourceLabel: '$sourcePrefix · $queryName',
              sourcePageUrl: references ?? 'https://www.gbif.org/',
            );
          }
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<_AudioResult?> _fetchINaturalistSound({
    required String commonName,
    required String scientificName,
    required String sourcePrefix,
  }) async {
    final queryName = _clean(scientificName).isNotEmpty
        ? _clean(scientificName)
        : _clean(commonName);

    if (queryName.isEmpty) return null;

    try {
      final uri = Uri.parse(
        'https://api.inaturalist.org/v1/observations'
        '?q=${Uri.encodeQueryComponent(queryName)}'
        '&sounds=true'
        '&quality_grade=research'
        '&per_page=30',
      );

      final response = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'ParkLifeMonitor/1.0',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'];

      if (results is! List) return null;

      for (final result in results.whereType<Map<String, dynamic>>()) {
        final sounds = result['sounds'];
        if (sounds is! List) continue;

        for (final sound in sounds.whereType<Map<String, dynamic>>()) {
          final fileUrl = sound['file_url']?.toString() ??
              sound['url']?.toString() ??
              sound['original_url']?.toString();

          final audioUrl = _normaliseAudioUrl(fileUrl);

          if (audioUrl != null) {
            return _AudioResult(
              audioUrl: audioUrl,
              sourceLabel: '$sourcePrefix · $queryName',
              sourcePageUrl:
                  result['uri']?.toString() ?? 'https://www.inaturalist.org/',
            );
          }
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  String _sourceLabelFromXenoItem(
    Map<String, dynamic> item,
    String sourcePrefix,
  ) {
    final quality = item['q']?.toString();
    final recordist = item['rec']?.toString();
    final country = item['cnt']?.toString();

    final parts = [
      sourcePrefix,
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
    if (type.contains('social')) score += 15;
    if (type.contains('echolocation')) score += 15;

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

  String? _normaliseAudioUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final value = raw.trim();

    if (value.startsWith('https://')) return value;
    if (value.startsWith('http://')) return value;
    if (value.startsWith('//')) return 'https:$value';

    return null;
  }

  bool _looksLikeAudioUrl(String url) {
    final lower = url.toLowerCase();

    return lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.m4a') ||
        lower.contains('/audio/') ||
        lower.contains('/sound') ||
        lower.contains('sound');
  }

  String _clean(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) return '';
    if (trimmed.toLowerCase() == 'unknown') return '';
    if (trimmed.toLowerCase().contains('possible')) return '';

    return trimmed;
  }

  String _normaliseName(String value) {
    return _clean(value)
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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

const Map<String, _AudioResult> _knownBirdAudioByName = {
  'turdus merula': _AudioResult(
    audioUrl: 'https://xeno-canto.org/125792/download',
    sourceLabel: 'xeno-canto real recording · Common Blackbird · XC125792',
    sourcePageUrl: 'https://xeno-canto.org/125792',
  ),
  'common blackbird': _AudioResult(
    audioUrl: 'https://xeno-canto.org/125792/download',
    sourceLabel: 'xeno-canto real recording · Common Blackbird · XC125792',
    sourcePageUrl: 'https://xeno-canto.org/125792',
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

const Map<String, _AudioResult> _knownBatAudioByName = {

    'eptesicus serotinus': _AudioResult(
    audioUrl: 'https://xeno-canto.org/923069/download',
    sourceLabel: 'xeno-canto real bat recording · Eurasian Serotine · Eptesicus serotinus · XC923069',
    sourcePageUrl: 'https://xeno-canto.org/923069',
  ),
  'serotine': _AudioResult(
    audioUrl: 'https://xeno-canto.org/923069/download',
    sourceLabel: 'xeno-canto real bat recording · Eurasian Serotine · Eptesicus serotinus · XC923069',
    sourcePageUrl: 'https://xeno-canto.org/923069',
  ),
  'myotis daubentonii': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Myotis_daubentonii.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Daubenton’s Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  "daubenton's bat": _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Myotis_daubentonii.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Daubenton’s Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  'daubentons bat': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Myotis_daubentonii.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Daubenton’s Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),

  'myotis mystacinus': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Myotis_mystacinus.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Whiskered Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  'whiskered bat': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Myotis_mystacinus.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Whiskered Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),

  'myotis nattereri': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Myotis_nattereri.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Natterer’s Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  "natterer's bat": _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Myotis_nattereri.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Natterer’s Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),

  'nyctalus leisleri': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Nyctalus_leisleri.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Leisler’s Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  "leisler's bat": _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Nyctalus_leisleri.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Leisler’s Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  'leislers bat': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Nyctalus_leisleri.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Leisler’s Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),

  'pipistrellus nathusii': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Pipistrellus_nathusii.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Nathusius’ Pipistrelle',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  "nathusius' pipistrelle": _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Pipistrellus_nathusii.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Nathusius’ Pipistrelle',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  'nathusius pipistrelle': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Pipistrellus_nathusii.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Nathusius’ Pipistrelle',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),

  'pipistrellus pipistrellus': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Pipistrellus_pipistrellus.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Common Pipistrelle',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  'common pipistrelle': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Pipistrellus_pipistrellus.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Common Pipistrelle',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),

  'pipistrellus pygmaeus': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Pipistrellus_pygmaeus.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Soprano Pipistrelle',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  'soprano pipistrelle': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Pipistrellus_pygmaeus.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Soprano Pipistrelle',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),

  'plecotus auritus': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Plecotus_auritus.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Brown Long-eared Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  'brown long eared bat': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Plecotus_auritus.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Brown Long-eared Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  'brown long-eared bat': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Plecotus_auritus.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Brown Long-eared Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),

  'rhinolophus hipposideros': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Rhinolophus_hipposideros.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Lesser Horseshoe Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
  'lesser horseshoe bat': _AudioResult(
    audioUrl: 'https://biodiversityireland.ie/resources/bats/wav_files/FullSpectrum_Rhinolophus_hipposideros.wav',
    sourceLabel: 'Biodiversity Ireland real Full Spectrum bat recording · Lesser Horseshoe Bat',
    sourcePageUrl: 'https://biodiversityireland.ie/resources/bats/bat-sounds.html',
  ),
};