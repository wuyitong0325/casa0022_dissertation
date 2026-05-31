import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/detection_event.dart';

class DetectionHistoryService extends ChangeNotifier {
  static const String _storageKey = 'park_life_detection_history';
  static const int maxEvents = 30;

  final List<DetectionEvent> _events = [];

  bool loaded = false;

  List<DetectionEvent> get events => List.unmodifiable(_events);

  DetectionHistoryService() {
    _load();
  }

  void addEvent(DetectionEvent event) {
    final exists = _events.any((item) {
      return item.timestamp == event.timestamp &&
          item.speciesKey == event.speciesKey &&
          item.type == event.type;
    });

    if (exists) return;

    _events.insert(0, event);

    if (_events.length > maxEvents) {
      _events.removeRange(maxEvents, _events.length);
    }

    _save();
    notifyListeners();
  }

  void clear() {
    _events.clear();
    _save();
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);

      if (raw == null || raw.trim().isEmpty) {
        loaded = true;
        notifyListeners();
        return;
      }

      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        loaded = true;
        notifyListeners();
        return;
      }

      final loadedEvents = decoded
          .whereType<Map<String, dynamic>>()
          .map(_fromJson)
          .whereType<DetectionEvent>()
          .toList();

      loadedEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _events
        ..clear()
        ..addAll(loadedEvents.take(maxEvents));

      loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('DetectionHistoryService load failed: $e');
      loaded = true;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final data = _events.take(maxEvents).map(_toJson).toList();

      await prefs.setString(_storageKey, jsonEncode(data));
    } catch (e) {
      debugPrint('DetectionHistoryService save failed: $e');
    }
  }

  Map<String, dynamic> _toJson(DetectionEvent event) {
    return {
      'device_id': event.deviceId,
      'type': event.type,
      'common_name': event.commonName,
      'scientific_name': event.scientificName,
      'confidence': event.confidence,
      'start_time': event.startTime,
      'end_time': event.endTime,
      'timestamp': event.timestamp.toIso8601String(),
    };
  }

  DetectionEvent? _fromJson(Map<String, dynamic> data) {
    try {
      final type = data['type']?.toString() ?? 'bird';

      return DetectionEvent(
        deviceId: data['device_id']?.toString() ?? 'wuyitong-pi',
        type: type,
        commonName: data['common_name']?.toString() ??
            data['commonName']?.toString() ??
            data['species']?.toString() ??
            (type == 'bat' ? 'Unknown Bat' : 'Unknown Bird'),
        scientificName: data['scientific_name']?.toString() ??
            data['scientificName']?.toString() ??
            'Unknown',
        confidence: _toDouble(data['confidence']) ?? 1.0,
        startTime: _toDouble(data['start_time'] ?? data['startTime']) ?? 0.0,
        endTime: _toDouble(data['end_time'] ?? data['endTime']) ?? 0.0,
        timestamp: DateTime.tryParse(data['timestamp']?.toString() ?? '') ??
            DateTime.now(),
      );
    } catch (e) {
      debugPrint('Invalid saved detection event: $e');
      return null;
    }
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}