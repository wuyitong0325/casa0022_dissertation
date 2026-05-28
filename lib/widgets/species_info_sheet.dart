import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import '../services/collection_service.dart';
import 'confidence_chip.dart';

class SpeciesInfoSheet extends StatefulWidget {
  final DetectionEvent event;
  final SpeciesProfile profile;
  final bool isLoading;

  const SpeciesInfoSheet({
    super.key,
    required this.event,
    required this.profile,
    this.isLoading = false,
  });

  @override
  State<SpeciesInfoSheet> createState() => _SpeciesInfoSheetState();
}

class _SpeciesInfoSheetState extends State<SpeciesInfoSheet> {
  final AudioPlayer _player = AudioPlayer();

  bool _isPlaying = false;

  Future<void> _toggleAudio() async {
    final url = widget.profile.audioUrl;

    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.event.isBat
                ? 'No human-audible bat reference sound is available yet.'
                : 'No online bird call recording was found for this species yet.',
          ),
        ),
      );
      return;
    }

    if (_isPlaying) {
      await _player.stop();
      setState(() => _isPlaying = false);
      return;
    }

    await _player.play(UrlSource(url));
    setState(() => _isPlaying = true);
  }

  @override
  Widget build(BuildContext context) {
    final collection = context.watch<CollectionService>();

    final event = widget.event;
    final profile = widget.profile;
    final key = event.speciesKey;

    final isFavourite = collection.isFavourite(key);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: profile.imageUrl == null
                  ? Text(
                      event.emoji,
                      style: const TextStyle(fontSize: 72),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: CachedNetworkImage(
                        imageUrl: profile.imageUrl!,
                        height: 190,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          height: 190,
                          color: const Color(0xFFE7EEDD),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          height: 190,
                          color: const Color(0xFFE7EEDD),
                          child: Center(
                            child: Text(
                              event.emoji,
                              style: const TextStyle(fontSize: 70),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.commonName,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => collection.toggleFavourite(key),
                  icon: Icon(
                    isFavourite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                  ),
                ),
              ],
            ),
            Text(
              event.scientificName,
              style: const TextStyle(
                color: Colors.black54,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
            ConfidenceChip(event: event),
            if (widget.isLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                'Loading online species information...',
                style: TextStyle(color: Colors.black54),
              ),
            ],
            const SizedBox(height: 18),
            _InfoBlock(title: 'What was detected?', body: profile.description),
            _InfoBlock(title: 'Habitat note', body: profile.habitatNote),
            _InfoBlock(title: 'Fun fact', body: profile.funFact),
            if (event.isBat)
              const _InfoBlock(
                title: 'About bat sounds',
                body:
                    'Bat echolocation is usually ultrasonic. If a reference sound is provided, it should be understood as a human-audible or time-expanded representation rather than the raw ultrasonic call.',
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _toggleAudio,
                    icon: Icon(
                      _isPlaying
                          ? Icons.stop_rounded
                          : Icons.volume_up_rounded,
                    ),
                    label: Text(_isPlaying ? 'Stop sound' : 'Play sound'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.eco_rounded),
                    label: const Text('Back'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              profile.sourceUrl == null
                  ? 'Source: ${profile.sourceLabel}'
                  : 'Source: ${profile.sourceLabel}\n${profile.sourceUrl}',
              style: const TextStyle(
                color: Colors.black45,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

class _InfoBlock extends StatelessWidget {
  final String title;
  final String body;

  const _InfoBlock({
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7EF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(body),
        ],
      ),
    );
  }
}