import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import '../services/mqtt_service.dart';
import '../services/online_species_service.dart';
import '../services/species_repository.dart';
import '../widgets/sound_wave_widget.dart';
import '../widgets/species_info_sheet.dart';

class SoundExplorerPage extends StatefulWidget {
  const SoundExplorerPage({super.key});

  @override
  State<SoundExplorerPage> createState() => _SoundExplorerPageState();
}

class _SoundExplorerPageState extends State<SoundExplorerPage> {
  String filter = 'all';
  double frequencyFeeling = 1.0;
  String? loadingKey;

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();

    final baseProfiles = SpeciesRepository.curatedProfiles;
    final onlineProfiles = mqtt.speciesProfiles.values.toList();

    final profiles = [
      ...baseProfiles,
      ...onlineProfiles.where(
        (p) => !baseProfiles.any(
          (b) =>
              b.commonName.toLowerCase() == p.commonName.toLowerCase() ||
              b.scientificName.toLowerCase() == p.scientificName.toLowerCase(),
        ),
      ),
    ].where((profile) {
      if (filter == 'all') return true;
      return profile.type == filter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sound Explorer'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Explore the park soundscape',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose a bird or bat species, load online information, and play reference sounds when available.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          SoundWaveWidget(
            active: true,
            intensity: frequencyFeeling,
          ),
          const SizedBox(height: 8),
          Text(
            filter == 'bat'
                ? 'Bat echolocation is ultrasonic. This slider visualises frequency intensity for human understanding.'
                : 'Bird calls are represented as audible acoustic patterns.',
            style: const TextStyle(color: Colors.black54),
          ),
          Slider(
            value: frequencyFeeling,
            min: 0.3,
            max: 1.6,
            divisions: 10,
            label: frequencyFeeling.toStringAsFixed(1),
            onChanged: (value) {
              setState(() => frequencyFeeling = value);
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: filter == 'all',
                onSelected: (_) => setState(() => filter = 'all'),
              ),
              ChoiceChip(
                label: const Text('Birds'),
                selected: filter == 'bird',
                onSelected: (_) => setState(() => filter = 'bird'),
              ),
              ChoiceChip(
                label: const Text('Bats'),
                selected: filter == 'bat',
                onSelected: (_) => setState(() => filter = 'bat'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final profile in profiles)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: _SoundSpeciesTile(
                profile: profile,
                isLoading: loadingKey ==
                    '${profile.type}:${profile.scientificName.toLowerCase()}',
                onTap: () => _openProfile(context, profile),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openProfile(
    BuildContext context,
    SpeciesProfile localProfile,
  ) async {
    final onlineService = context.read<OnlineSpeciesService>();

    final event = DetectionEvent(
      deviceId: 'sound-explorer',
      type: localProfile.type,
      commonName: localProfile.commonName,
      scientificName: localProfile.scientificName,
      confidence: 1,
      startTime: 0,
      endTime: 0,
      timestamp: DateTime.now(),
    );

    final key = '${localProfile.type}:${localProfile.scientificName.toLowerCase()}';

    setState(() {
      loadingKey = key;
    });

    SpeciesProfile profile = localProfile;

    try {
      profile = await onlineService.fetchProfile(event);
    } catch (_) {
      profile = localProfile;
    }

    if (!mounted) return;

    setState(() {
      loadingKey = null;
    });

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SpeciesInfoSheet(
        event: event,
        profile: profile,
        isLoading: false,
      ),
    );
  }
}

class _SoundSpeciesTile extends StatelessWidget {
  final SpeciesProfile profile;
  final bool isLoading;
  final VoidCallback onTap;

  const _SoundSpeciesTile({
    required this.profile,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isBat = profile.type == 'bat';

    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      tileColor: Colors.white,
      leading: Text(
        isBat ? '🦇' : '🐦',
        style: const TextStyle(fontSize: 34),
      ),
      title: Text(
        profile.commonName,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(profile.scientificName),
      trailing: isLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.info_outline_rounded),
      onTap: isLoading ? null : onTap,
    );
  }
}