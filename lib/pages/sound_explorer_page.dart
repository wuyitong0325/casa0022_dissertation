import 'dart:math';

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
  String labMode = 'bird';
  double frequency = 45;
  double noiseLevel = 0.25;
  String? guessResult;
  String? loadingKey;

  final Random _random = Random();

  String challenge = 'bird';

  @override
  void initState() {
    super.initState();
    _newChallenge();
  }

  void _newChallenge() {
    final options = ['bird', 'bat', 'noise'];
    challenge = options[_random.nextInt(options.length)];
    guessResult = null;
  }

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

    final simulatedConfidence =
        ((1.0 - noiseLevel) * 0.82 + 0.12).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sound Lab'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Sound Lab',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Explore how acoustic signals become AI wildlife detections.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),

          _LabModeCard(
            mode: labMode,
            onChanged: (value) {
              setState(() {
                labMode = value;
                if (value == 'bird') frequency = 6;
                if (value == 'bat') frequency = 65;
                if (value == 'noise') frequency = 15;
              });
            },
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'What the microphone hears',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 8),
                SoundWaveWidget(
                  active: true,
                  intensity: labMode == 'bat'
                      ? 1.45
                      : labMode == 'noise'
                          ? 0.65
                          : 1.0,
                ),
                const SizedBox(height: 8),
                Text(
                  _modeExplanation(labMode),
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          _FrequencyExplorer(
            frequency: frequency,
            onChanged: (value) {
              setState(() {
                frequency = value;
              });
            },
          ),

          const SizedBox(height: 14),

          _ConfidenceSimulator(
            noiseLevel: noiseLevel,
            confidence: simulatedConfidence,
            onChanged: (value) {
              setState(() {
                noiseLevel = value;
              });
            },
          ),

          const SizedBox(height: 14),

          _GuessSoundCard(
            challenge: challenge,
            result: guessResult,
            onGuess: (guess) {
              setState(() {
                guessResult = guess == challenge
                    ? 'Correct! The AI-style label is ${challenge.toUpperCase()}.'
                    : 'Not quite. This one behaves more like ${challenge.toUpperCase()}.';
              });
            },
            onNext: () {
              setState(() {
                _newChallenge();
              });
            },
          ),

          const SizedBox(height: 24),
          const Text(
            'Reference species',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap a species to load a clean card with online image, description and playable sound when available.',
            style: TextStyle(color: Colors.black54),
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

          const SizedBox(height: 14),

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

  String _modeExplanation(String mode) {
    if (mode == 'bat') {
      return 'Bat echolocation is often ultrasonic. The phone may not reproduce it, but UltraMic can record it at high sample rates.';
    }
    if (mode == 'noise') {
      return 'Urban noise can confuse classifiers. Higher noise usually lowers confidence.';
    }
    return 'Bird calls are usually audible and often contain repeated patterns that AI models can classify.';
  }

  Future<void> _openProfile(
  BuildContext context,
  SpeciesProfile localProfile,
) async {
  final onlineService = context.read<OnlineSpeciesService>();

  final event = DetectionEvent(
    deviceId: 'sound-lab',
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

  if (!context.mounted) return;

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

class _LabModeCard extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;

  const _LabModeCard({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose a signal type',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                label: const Text('🐦 Bird call'),
                selected: mode == 'bird',
                onSelected: (_) => onChanged('bird'),
              ),
              ChoiceChip(
                label: const Text('🦇 Bat pulse'),
                selected: mode == 'bat',
                onSelected: (_) => onChanged('bat'),
              ),
              ChoiceChip(
                label: const Text('🌫 Urban noise'),
                selected: mode == 'noise',
                onSelected: (_) => onChanged('noise'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FrequencyExplorer extends StatelessWidget {
  final double frequency;
  final ValueChanged<double> onChanged;

  const _FrequencyExplorer({
    required this.frequency,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = frequency < 12
        ? 'Mostly audible: bird calls / human hearing'
        : frequency < 20
            ? 'Upper audible range'
            : 'Ultrasonic: bat echolocation range';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Frequency Explorer',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            '${frequency.toStringAsFixed(0)} kHz · $label',
            style: const TextStyle(color: Colors.black54),
          ),
          Slider(
            value: frequency,
            min: 2,
            max: 120,
            divisions: 59,
            onChanged: onChanged,
          ),
          const Text(
            'This explains why a phone speaker may play a “bat sound” but still fail to trigger BatDetect2: real echolocation is often above normal speaker and human hearing range.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceSimulator extends StatelessWidget {
  final double noiseLevel;
  final double confidence;
  final ValueChanged<double> onChanged;

  const _ConfidenceSimulator({
    required this.noiseLevel,
    required this.confidence,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI Confidence Simulator',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            'Noise level: ${(noiseLevel * 100).toStringAsFixed(0)}% · Simulated confidence: ${(confidence * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.black54),
          ),
          Slider(
            value: noiseLevel,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: onChanged,
          ),
          LinearProgressIndicator(value: confidence),
        ],
      ),
    );
  }
}

class _GuessSoundCard extends StatelessWidget {
  final String challenge;
  final String? result;
  final ValueChanged<String> onGuess;
  final VoidCallback onNext;

  const _GuessSoundCard({
    required this.challenge,
    required this.result,
    required this.onGuess,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final emoji = challenge == 'bird'
        ? '🐦'
        : challenge == 'bat'
            ? '🦇'
            : '🌫';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Guess the Sound',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            '$emoji A mystery acoustic pattern appears. What would the AI probably label it as?',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(
                onPressed: () => onGuess('bird'),
                child: const Text('🐦 Bird'),
              ),
              FilledButton(
                onPressed: () => onGuess('bat'),
                child: const Text('🦇 Bat'),
              ),
              OutlinedButton(
                onPressed: () => onGuess('noise'),
                child: const Text('🌫 Noise'),
              ),
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: 12),
            Text(
              result!,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Next challenge'),
            ),
          ],
        ],
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