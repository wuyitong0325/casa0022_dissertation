import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/detection_event.dart';
import '../models/species_profile.dart';
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

  bool isPlaying = false;
  String? playError;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _playSound() async {
    final audioUrl = widget.profile.audioUrl;

    if (widget.event.isBat) {
      setState(() {
        playError = 'Bat audio resolver will be added after supervisor discussion.';
      });
      return;
    }

    if (audioUrl == null || audioUrl.trim().isEmpty) {
      setState(() {
        playError =
            'Real bird recording is still loading. Close and reopen this card, or check network connection.';
      });
      return;
    }

    setState(() {
      isPlaying = true;
      playError = null;
    });

    try {
      await _player.stop();
      await _player.play(UrlSource(audioUrl));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.profile.audioSourceLabel == null
                ? 'Playing real bird recording.'
                : 'Playing ${widget.profile.audioSourceLabel}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        playError =
            'This recording URL could not be played on this device. Try another network or reopen the card.';
      });
    } finally {
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) {
        setState(() {
          isPlaying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final profile = widget.profile;
    final isBat = event.isBat;

    final hasAudio = !isBat &&
        profile.audioUrl != null &&
        profile.audioUrl!.trim().isNotEmpty;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.84,
      minChildSize: 0.48,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            if (profile.imageUrl != null && profile.imageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: CachedNetworkImage(
                  imageUrl: profile.imageUrl!,
                  height: 220,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _ImagePlaceholder(isBat: isBat),
                  errorWidget: (_, __, ___) => _ImagePlaceholder(isBat: isBat),
                ),
              )
            else
              _ImagePlaceholder(isBat: isBat),

            const SizedBox(height: 18),

            Row(
              children: [
                Text(
                  isBat ? '🦇' : '🐦',
                  style: const TextStyle(fontSize: 42),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    profile.commonName,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            Text(
              profile.scientificName,
              style: const TextStyle(
                fontSize: 17,
                color: Colors.black54,
                fontStyle: FontStyle.italic,
              ),
            ),

            const SizedBox(height: 12),

            ConfidenceChip(event: event),

            const SizedBox(height: 18),

            FilledButton.icon(
              onPressed: widget.isLoading || isPlaying ? null : _playSound,
              icon: Icon(
                isPlaying
                    ? Icons.graphic_eq_rounded
                    : hasAudio
                        ? Icons.play_arrow_rounded
                        : Icons.cloud_sync_rounded,
              ),
              label: Text(
                isBat
                    ? 'Bat sound coming later'
                    : isPlaying
                        ? 'Playing real bird recording...'
                        : hasAudio
                            ? 'Play real bird recording'
                            : 'Load real bird recording',
              ),
            ),

            if (playError != null) ...[
              const SizedBox(height: 10),
              Text(
                playError!,
                style: const TextStyle(
                  color: Colors.deepOrange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],

            if (profile.audioSourceLabel != null ||
                profile.audioSourceUrl != null) ...[
              const SizedBox(height: 10),
              _InfoCard(
                title: 'Audio source',
                body: [
                  if (profile.audioSourceLabel != null)
                    profile.audioSourceLabel!,
                  if (profile.audioSourceUrl != null)
                    profile.audioSourceUrl!,
                ].join('\n'),
              ),
            ],

            const SizedBox(height: 18),

            _InfoCard(
              title: 'About this species',
              body: profile.description,
            ),

            const SizedBox(height: 12),

            _InfoCard(
              title: 'Habitat note',
              body: profile.habitatNote,
            ),

            const SizedBox(height: 12),

            _InfoCard(
              title: 'Fun fact',
              body: profile.funFact,
            ),

            const SizedBox(height: 12),

            _InfoCard(
              title: 'Detection note',
              body: isBat
                  ? 'Bat audio will be connected through a dedicated bat sound resolver after the data source is confirmed.'
                  : 'This card uses xeno-canto to retrieve a real bird recording for the detected or selected species.',
            ),

            if (profile.sourceLabel != null || profile.sourceUrl != null) ...[
              const SizedBox(height: 12),
              _InfoCard(
                title: 'Species source',
                body: [
                  if (profile.sourceLabel != null) profile.sourceLabel!,
                  if (profile.sourceUrl != null) profile.sourceUrl!,
                ].join('\n'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final bool isBat;

  const _ImagePlaceholder({
    required this.isBat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: isBat
              ? [
                  const Color(0xFF171B3F),
                  const Color(0xFF4F3A86),
                ]
              : [
                  const Color(0xFFDFF5D7),
                  const Color(0xFFBEE5FF),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          isBat ? '🦇' : '🐦',
          style: const TextStyle(fontSize: 96),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;

  const _InfoCard({
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF4),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            body,
            style: const TextStyle(
              height: 1.45,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}