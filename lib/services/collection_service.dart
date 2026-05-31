import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/detection_event.dart';

class CollectionService extends ChangeNotifier {
  static const String _unlockedKey = 'park_life_unlocked_species';
  static const String _favouriteKey = 'park_life_favourite_species';

  final Set<String> _unlockedSpecies = <String>{};
  final Set<String> _favouriteSpecies = <String>{};

  bool _loaded = false;

  Set<String> get unlockedSpecies => Set.unmodifiable(_unlockedSpecies);

  Set<String> get favouriteSpecies => Set.unmodifiable(_favouriteSpecies);

  int get unlockedCount => _unlockedSpecies.length;

  int get favouriteCount => _favouriteSpecies.length;

  bool get loaded => _loaded;

  CollectionService() {
    _loadFromStorage();
  }

  bool isUnlocked(String speciesKey) {
    return _unlockedSpecies.contains(speciesKey);
  }

  bool isFavourite(String speciesKey) {
    return _favouriteSpecies.contains(speciesKey);
  }

  void unlockFromEvent(DetectionEvent event) {
    unlockSpecies(event.speciesKey);
  }

  void unlockSpecies(String speciesKey) {
    final cleanKey = speciesKey.trim();
    if (cleanKey.isEmpty) return;

    final changed = _unlockedSpecies.add(cleanKey);

    if (changed) {
      _saveToStorage();
      notifyListeners();
    }
  }

  void lockSpecies(String speciesKey) {
    final changed = _unlockedSpecies.remove(speciesKey);

    if (changed) {
      _favouriteSpecies.remove(speciesKey);
      _saveToStorage();
      notifyListeners();
    }
  }

  void toggleFavourite(String speciesKey) {
    final cleanKey = speciesKey.trim();
    if (cleanKey.isEmpty) return;

    if (!_unlockedSpecies.contains(cleanKey)) {
      _unlockedSpecies.add(cleanKey);
    }

    if (_favouriteSpecies.contains(cleanKey)) {
      _favouriteSpecies.remove(cleanKey);
    } else {
      _favouriteSpecies.add(cleanKey);
    }

    _saveToStorage();
    notifyListeners();
  }

  void clearFavourites() {
    _favouriteSpecies.clear();
    _saveToStorage();
    notifyListeners();
  }

  void clearCollection() {
    _unlockedSpecies.clear();
    _favouriteSpecies.clear();
    _saveToStorage();
    notifyListeners();
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final unlockedRaw = prefs.getString(_unlockedKey);
      final favouriteRaw = prefs.getString(_favouriteKey);

      if (unlockedRaw != null && unlockedRaw.isNotEmpty) {
        final decoded = jsonDecode(unlockedRaw);

        if (decoded is List) {
          _unlockedSpecies
            ..clear()
            ..addAll(decoded.map((item) => item.toString()));
        }
      }

      if (favouriteRaw != null && favouriteRaw.isNotEmpty) {
        final decoded = jsonDecode(favouriteRaw);

        if (decoded is List) {
          _favouriteSpecies
            ..clear()
            ..addAll(decoded.map((item) => item.toString()));
        }
      }

      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('CollectionService load failed: $e');
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        _unlockedKey,
        jsonEncode(_unlockedSpecies.toList()),
      );

      await prefs.setString(
        _favouriteKey,
        jsonEncode(_favouriteSpecies.toList()),
      );
    } catch (e) {
      debugPrint('CollectionService save failed: $e');
    }
  }
}