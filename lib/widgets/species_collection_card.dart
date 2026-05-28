import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import '../services/collection_service.dart';

class SpeciesCollectionCard extends StatelessWidget {
  final SpeciesProfile profile;
  final bool unlocked;

  const SpeciesCollectionCard({
    super.key,
    required this.profile,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    final collection = context.watch<CollectionService>();

    final fakeEvent = DetectionEvent(
      deviceId: 'collection',
      type: profile.type,
      commonName: profile.commonName,
      scientificName: profile.scientificName,
      confidence: 1,
      startTime: 0,
      endTime: 0,
      timestamp: DateTime.now(),
    );

    final key = fakeEvent.speciesKey;
    final favourite = collection.isFavourite(key);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: unlocked ? Colors.white : const Color(0xFFF1F1F1),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: unlocked ? const Color(0xFFB7D9B8) : Colors.black12,
        ),
      ),
      child: Row(
        children: [
          Text(
            unlocked
                ? profile.type == 'bat'
                    ? '🦇'
                    : '🐦'
                : '❔',
            style: const TextStyle(fontSize: 38),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unlocked ? profile.commonName : 'Undiscovered species',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  unlocked
                      ? profile.scientificName
                      : 'Listen to the park to unlock this species.',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: unlocked ? () => collection.toggleFavourite(key) : null,
            icon: Icon(
              favourite ? Icons.favorite_rounded : Icons.favorite_border,
              color: favourite ? Colors.red : null,
            ),
          ),
        ],
      ),
    );
  }
}