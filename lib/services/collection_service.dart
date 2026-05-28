import 'package:flutter/foundation.dart';

import '../models/detection_event.dart';

class CollectionService extends ChangeNotifier {
  final Set<String> _unlockedSpecies = {};
  final Set<String> _favouriteSpecies = {};

  Set<String> get unlockedSpecies => _unlockedSpecies;
  Set<String> get favouriteSpecies => _favouriteSpecies;

  void unlockFromEvent(DetectionEvent event) {
    _unlockedSpecies.add(event.speciesKey);
    notifyListeners();
  }

  bool isUnlocked(String key) {
    return _unlockedSpecies.contains(key);
  }

  bool isFavourite(String key) {
    return _favouriteSpecies.contains(key);
  }

  void toggleFavourite(String key) {
    if (_favouriteSpecies.contains(key)) {
      _favouriteSpecies.remove(key);
    } else {
      _favouriteSpecies.add(key);
      _unlockedSpecies.add(key);
    }

    notifyListeners();
  }

  void clearCollection() {
    _unlockedSpecies.clear();
    _favouriteSpecies.clear();
    notifyListeners();
  }
}