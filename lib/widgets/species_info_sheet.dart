import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  bool isDownloadingAudio = false;
  String? playError;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _playSound() async {
    final audioUrl = widget.profile.audioUrl;

    if (audioUrl == null || audioUrl.trim().isEmpty) {
      setState(() {
        playError = widget.event.isBat
            ? 'No verified bat recording is attached to this species yet.'
            : 'No verified bird recording is attached to this species yet.';
      });
      return;
    }

    setState(() {
      isDownloadingAudio = true;
      isPlaying = false;
      playError = null;
    });

    try {
      final audioBytes = await _downloadAudioBytes(audioUrl);

      if (!mounted) return;

      if (audioBytes == null || audioBytes.lengthInBytes < 1000) {
        setState(() {
          playError =
              'The recording link responded, but no valid audio data was downloaded.';
          isDownloadingAudio = false;
        });
        return;
      }

      setState(() {
        isDownloadingAudio = false;
        isPlaying = true;
      });

      await _player.stop();
      await _player.play(BytesSource(audioBytes));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.profile.audioSourceLabel ??
                'Playing real wildlife recording.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        playError = 'Audio download/playback failed: $e';
        isDownloadingAudio = false;
        isPlaying = false;
      });
    } finally {
      await Future.delayed(const Duration(milliseconds: 900));

      if (mounted) {
        setState(() {
          isPlaying = false;
          isDownloadingAudio = false;
        });
      }
    }
  }

  Future<Uint8List?> _downloadAudioBytes(String rawUrl) async {
    final urlsToTry = <String>[
      rawUrl,
      if (!rawUrl.contains('/download') &&
          widget.profile.audioSourceUrl != null &&
          widget.profile.audioSourceUrl!.contains('xeno-canto.org/'))
        '${widget.profile.audioSourceUrl}/download',
    ];

    for (final url in urlsToTry) {
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: const {
            'User-Agent': 'Mozilla/5.0 ParkLifeMonitor/1.0 Flutter Android',
            'Accept': 'audio/wav,audio/x-wav,audio/ogg,audio/mpeg,audio/*,*/*',
          },
        ).timeout(const Duration(seconds: 25));

        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }

        final bytes = response.bodyBytes;
        final contentType =
            response.headers['content-type']?.toLowerCase() ?? '';

        final looksLikeAudio = contentType.contains('audio') ||
            contentType.contains('wav') ||
            contentType.contains('ogg') ||
            _looksLikeMp3(bytes) ||
            _looksLikeOgg(bytes) ||
            _looksLikeWav(bytes);

        if (bytes.lengthInBytes > 1000 && looksLikeAudio) {
          return bytes;
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  bool _looksLikeMp3(Uint8List bytes) {
    if (bytes.length < 3) return false;

    final hasId3 = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
    final hasMp3Frame = bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;

    return hasId3 || hasMp3Frame;
  }

  bool _looksLikeOgg(Uint8List bytes) {
    if (bytes.length < 4) return false;

    return bytes[0] == 0x4F &&
        bytes[1] == 0x67 &&
        bytes[2] == 0x67 &&
        bytes[3] == 0x53;
  }

  bool _looksLikeWav(Uint8List bytes) {
    if (bytes.length < 12) return false;

    return bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45;
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final profile = widget.profile;
    final isBat = event.isBat;
    final hasAudio = profile.audioUrl != null && profile.audioUrl!.isNotEmpty;

    final buttonLabel = isDownloadingAudio
        ? 'Downloading real wildlife recording...'
        : isPlaying
            ? 'Playing real wildlife recording...'
            : hasAudio
                ? isBat
                    ? 'Play real bat recording'
                    : 'Play real bird recording'
                : isBat
                    ? 'No verified bat sound attached'
                    : 'No verified bird sound attached';

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
              onPressed: widget.isLoading || isPlaying || isDownloadingAudio
                  ? null
                  : _playSound,
              icon: Icon(
                isDownloadingAudio
                    ? Icons.downloading_rounded
                    : isPlaying
                        ? Icons.graphic_eq_rounded
                        : hasAudio
                            ? Icons.play_arrow_rounded
                            : Icons.cloud_off_rounded,
              ),
              label: Text(buttonLabel),
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
                  ? 'Bat audio is linked to a real bat recording source when available. Some files are full-spectrum detector recordings rather than phone-speaker test sounds.'
                  : 'Bird audio is linked to a real xeno-canto recording where available.',
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