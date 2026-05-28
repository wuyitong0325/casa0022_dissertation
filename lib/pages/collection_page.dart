import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import '../services/collection_service.dart';
import '../services/mqtt_service.dart';
import '../services/species_repository.dart';
import '../widgets/species_collection_card.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  String filter = 'all';

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();
    final collection = context.watch<CollectionService>();

    final profiles = <SpeciesProfile>[
      ...SpeciesRepository.curatedProfiles,
      ...mqtt.speciesProfiles.values.where(
        (p) => !SpeciesRepository.curatedProfiles.any(
          (b) =>
              b.commonName.toLowerCase() == p.commonName.toLowerCase() ||
              b.scientificName.toLowerCase() == p.scientificName.toLowerCase(),
        ),
      ),
    ];

    final filtered = profiles.where((profile) {
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

      if (filter == 'birds') return profile.type == 'bird';
      if (filter == 'bats') return profile.type == 'bat';
      if (filter == 'unlocked') return collection.isUnlocked(key);
      if (filter == 'favourites') return collection.isFavourite(key);

      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Species Collection'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Wildlife collection',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Detected species are unlocked automatically. Favourite species to build your own park field guide.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: 'All',
                value: 'all',
                group: filter,
                onTap: _setFilter,
              ),
              _FilterChip(
                label: 'Birds',
                value: 'birds',
                group: filter,
                onTap: _setFilter,
              ),
              _FilterChip(
                label: 'Bats',
                value: 'bats',
                group: filter,
                onTap: _setFilter,
              ),
              _FilterChip(
                label: 'Unlocked',
                value: 'unlocked',
                group: filter,
                onTap: _setFilter,
              ),
              _FilterChip(
                label: 'Favourites',
                value: 'favourites',
                group: filter,
                onTap: _setFilter,
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final profile in filtered)
            Builder(
              builder: (context) {
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

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SpeciesCollectionCard(
                    profile: profile,
                    unlocked: collection.isUnlocked(fakeEvent.speciesKey),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _setFilter(String value) {
    setState(() => filter = value);
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String group;
  final ValueChanged<String> onTap;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: value == group,
      onSelected: (_) => onTap(value),
    );
  }
}