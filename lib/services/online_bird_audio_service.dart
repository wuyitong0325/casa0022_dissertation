import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class BirdRecordingResult {
  final String id;
  final String commonName;
  final String scientificName;
  final String quality;
  final String type;
  final String country;
  final String location;
  final String recordist;
  final String pageUrl;
  final String fileUrl;
  final String localFilePath;

  const BirdRecordingResult({
    required this.id,
    required this.commonName,
    required this.scientificName,
    required this.quality,
    required this.type,
    required this.country,
    required this.location,
    required this.recordist,
    required this.pageUrl,
    required this.fileUrl,
    required this.localFilePath,
  });

  String get sourceLabel {
    final typeText = type.trim().isEmpty ? 'bird recording' : type;
    final countryText = country.trim().isEmpty ? 'unknown country' : country;
    final recordistText =
        recordist.trim().isEmpty ? 'xeno-canto contributor' : recordist;

    return 'xeno-canto · $typeText · $countryText · $recordistText';
  }
}

class OnlineBirdAudioService {
  static const String _apiEndpoint =
      'https://xeno-canto.org/api/3/recordings';

  static const String _apiKey = String.fromEnvironment(
    'XENO_CANTO_API_KEY',
    defaultValue: 'demo',
  );

  static const int _maxCacheFiles = 50;

  Future<BirdRecordingResult?> findAndCacheBestRecording({
    required String commonName,
    required String scientificName,
  }) async {
    final queries = _buildQueries(
      commonName: commonName,
      scientificName: scientificName,
    );

    debugPrint('XC v3 audio search for: $commonName / $scientificName');
    debugPrint('XC key empty: ${_apiKey.trim().isEmpty}');
    debugPrint('XC query list: $queries');

    final seenIds = <String>{};
    final candidates = <_XenoCantoRecording>[];

    for (final query in queries) {
      final results = await _searchXenoCanto(query: query);

      debugPrint('XC query "$query" returned ${results.length} result(s).');

      for (final recording in results) {
        if (recording.id.isEmpty) continue;
        if (recording.fileUrl.trim().isEmpty) continue;

        if (seenIds.add(recording.id)) {
          candidates.add(recording);
        }
      }

      if (candidates.length >= 20) break;
    }

    debugPrint('XC total unique candidates: ${candidates.length}');

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort(_compareRecordings);

    for (final recording in candidates.take(12)) {
      debugPrint(
        'Trying XC ${recording.id}: '
        '${recording.commonName} / ${recording.scientificName}, '
        'q=${recording.quality}, type=${recording.type}, file=${recording.fileUrl}',
      );

      try {
        final localPath = await _downloadToCache(recording);

        if (localPath == null) {
          debugPrint('XC ${recording.id} download returned null.');
          continue;
        }

        await _pruneOldCacheFiles();

        return BirdRecordingResult(
          id: recording.id,
          commonName: recording.commonName,
          scientificName: recording.scientificName,
          quality: recording.quality,
          type: recording.type,
          country: recording.country,
          location: recording.location,
          recordist: recording.recordist,
          pageUrl: recording.pageUrl,
          fileUrl: recording.fileUrl,
          localFilePath: localPath,
        );
      } catch (e) {
        debugPrint('Failed to cache xeno-canto recording ${recording.id}: $e');
      }
    }

    return null;
  }

  List<String> _buildQueries({
    required String commonName,
    required String scientificName,
  }) {
    final queries = <String>[];

    final sci = scientificName.trim();
    final common = commonName.trim();

    final sciLower = sci.toLowerCase();
    final commonLower = common.toLowerCase();

    if (sci.isNotEmpty &&
        sciLower != 'unknown' &&
        !sciLower.contains('unknown')) {
      queries.add('sp:"$sci"');

      final parts = sci.split(RegExp(r'\s+'));

      if (parts.length >= 2) {
        final genus = parts[0];
        final species = parts[1];

        queries.add('gen:$genus sp:$species');
        queries.add('gen:$genus sp:$species q:A');
        queries.add('gen:$genus sp:$species q:B');
        queries.add('sp:"$genus $species" q:A');
        queries.add('sp:"$genus $species" q:B');
      }
    }

    if (common.isNotEmpty &&
        commonLower != 'unknown bird' &&
        !commonLower.contains('unknown')) {
      queries.add('en:"$common"');
      queries.add('"$common"');
      queries.add(common);
    }

    return queries;
  }

  Future<List<_XenoCantoRecording>> _searchXenoCanto({
    required String query,
  }) async {
    final key = _apiKey.trim();

    final uri = Uri.parse(_apiEndpoint).replace(
      queryParameters: <String, String>{
        'query': query,
        'key': key.isEmpty ? 'demo' : key,
      },
    );

    debugPrint('Searching xeno-canto v3: $uri');

    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'ParkLifeMonitor/1.0',
        'Accept': 'application/json',
      },
    ).timeout(
      const Duration(seconds: 15),
    );

    debugPrint(
      'XC API response: ${response.statusCode}, bytes=${response.bodyBytes.length}',
    );

    if (response.statusCode != 200) {
      final preview = response.body.length > 200
          ? response.body.substring(0, 200)
          : response.body;
      debugPrint('XC API error preview: $preview');
      return <_XenoCantoRecording>[];
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      return <_XenoCantoRecording>[];
    }

    final recordingsRaw = decoded['recordings'];
    final numRecordings = decoded['numRecordings'];

    debugPrint('XC numRecordings: $numRecordings');

    if (recordingsRaw is! List) {
      return <_XenoCantoRecording>[];
    }

    return recordingsRaw
        .whereType<Map<String, dynamic>>()
        .map(_XenoCantoRecording.fromJson)
        .where((recording) => recording.fileUrl.trim().isNotEmpty)
        .toList();
  }

  int _compareRecordings(
    _XenoCantoRecording a,
    _XenoCantoRecording b,
  ) {
    final qualityCompare = _qualityScore(b.quality).compareTo(
      _qualityScore(a.quality),
    );

    if (qualityCompare != 0) return qualityCompare;

    final typeCompare = _typeScore(b.type).compareTo(
      _typeScore(a.type),
    );

    if (typeCompare != 0) return typeCompare;

    return a.id.compareTo(b.id);
  }

  int _qualityScore(String quality) {
    switch (quality.toUpperCase().trim()) {
      case 'A':
        return 5;
      case 'B':
        return 4;
      case 'C':
        return 3;
      case 'D':
        return 2;
      case 'E':
        return 1;
      default:
        return 0;
    }
  }

  int _typeScore(String type) {
    final lower = type.toLowerCase();

    if (lower.contains('song')) return 5;
    if (lower.contains('call')) return 4;
    if (lower.contains('alarm')) return 3;
    if (lower.contains('flight')) return 2;

    return 1;
  }

  Future<String?> _downloadToCache(_XenoCantoRecording recording) async {
    final cacheDir = await getTemporaryDirectory();
    final audioDir = Directory('${cacheDir.path}/park_life_bird_audio');

    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }

    final extension = _guessExtension(recording.fileUrl);
    final safeName = _safeFileName(
      '${recording.scientificName}_${recording.id}$extension',
    );

    final file = File('${audioDir.path}/$safeName');

    if (await file.exists() && await file.length() > 4096) {
      debugPrint('Using cached XC audio: ${file.path}');
      return file.path;
    }

    final fileUri = _normaliseAudioUrl(recording.fileUrl);

    debugPrint('Downloading xeno-canto audio: $fileUri');

    final response = await http.get(
      fileUri,
      headers: const {
        'User-Agent': 'ParkLifeMonitor/1.0',
        'Accept': 'audio/mpeg,audio/*,*/*',
      },
    ).timeout(
      const Duration(seconds: 30),
    );

    final contentType = response.headers['content-type'] ?? '';
    final bytes = response.bodyBytes;

    debugPrint(
      'XC audio response: ${response.statusCode}, '
      'content-type=$contentType, bytes=${bytes.length}',
    );

    if (response.statusCode != 200) {
      return null;
    }

    final looksLikeAudio = _looksLikeAudio(contentType, bytes);

    if (!looksLikeAudio) {
      final preview = utf8.decode(
        bytes.take(120).toList(),
        allowMalformed: true,
      );

      debugPrint('Downloaded data does not look like audio. Preview: $preview');
      return null;
    }

    await file.writeAsBytes(bytes, flush: true);

    final length = await file.length();

    if (length <= 4096) {
      await file.delete();
      return null;
    }

    debugPrint('Saved XC audio to ${file.path}, bytes=$length');

    return file.path;
  }

  bool _looksLikeAudio(String contentType, List<int> bytes) {
    final lowerType = contentType.toLowerCase();

    if (lowerType.contains('audio')) return true;
    if (lowerType.contains('mpeg')) return true;
    if (lowerType.contains('octet-stream')) return true;

    if (bytes.length < 4) return false;

    final hasId3 = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
    final hasMp3Frame = bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
    final hasOgg = bytes[0] == 0x4F &&
        bytes[1] == 0x67 &&
        bytes[2] == 0x67 &&
        bytes[3] == 0x53;
    final hasRiff = bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46;

    return hasId3 || hasMp3Frame || hasOgg || hasRiff;
  }

  Uri _normaliseAudioUrl(String rawUrl) {
    final clean = rawUrl.trim();

    if (clean.startsWith('//')) {
      return Uri.parse('https:$clean');
    }

    if (clean.startsWith('/')) {
      return Uri.parse('https://xeno-canto.org$clean');
    }

    if (clean.startsWith('http://')) {
      return Uri.parse(clean.replaceFirst('http://', 'https://'));
    }

    return Uri.parse(clean);
  }

  String _guessExtension(String url) {
    final lower = url.toLowerCase();

    if (lower.contains('.wav')) return '.wav';
    if (lower.contains('.ogg')) return '.ogg';
    if (lower.contains('.m4a')) return '.m4a';
    if (lower.contains('.mp3')) return '.mp3';

    return '.mp3';
  }

  String _safeFileName(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  Future<void> _pruneOldCacheFiles() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final audioDir = Directory('${cacheDir.path}/park_life_bird_audio');

      if (!await audioDir.exists()) return;

      final files = await audioDir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();

      if (files.length <= _maxCacheFiles) return;

      files.sort((a, b) {
        final aModified = a.lastModifiedSync();
        final bModified = b.lastModifiedSync();

        return bModified.compareTo(aModified);
      });

      for (final file in files.skip(_maxCacheFiles)) {
        try {
          await file.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Audio cache prune failed: $e');
    }
  }

  Future<void> clearAudioCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final audioDir = Directory('${cacheDir.path}/park_life_bird_audio');

      if (await audioDir.exists()) {
        await audioDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Clear bird audio cache failed: $e');
    }
  }
}

class _XenoCantoRecording {
  final String id;
  final String commonName;
  final String scientificName;
  final String quality;
  final String type;
  final String country;
  final String location;
  final String recordist;
  final String pageUrl;
  final String fileUrl;

  const _XenoCantoRecording({
    required this.id,
    required this.commonName,
    required this.scientificName,
    required this.quality,
    required this.type,
    required this.country,
    required this.location,
    required this.recordist,
    required this.pageUrl,
    required this.fileUrl,
  });

  factory _XenoCantoRecording.fromJson(Map<String, dynamic> json) {
    final genus = json['gen']?.toString() ?? '';
    final species = json['sp']?.toString() ?? '';
    final scientificName = '$genus $species'.trim();

    final id = json['id']?.toString() ?? '';

    final file = (json['file'] ??
            json['file-name'] ??
            json['fileName'] ??
            json['sono']?['small'] ??
            '')
        .toString();

    return _XenoCantoRecording(
      id: id,
      commonName: json['en']?.toString() ?? '',
      scientificName: scientificName,
      quality: json['q']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      country: json['cnt']?.toString() ?? '',
      location: json['loc']?.toString() ?? '',
      recordist: json['rec']?.toString() ?? '',
      pageUrl: id.isEmpty
          ? 'https://xeno-canto.org'
          : 'https://xeno-canto.org/$id',
      fileUrl: file,
    );
  }
}