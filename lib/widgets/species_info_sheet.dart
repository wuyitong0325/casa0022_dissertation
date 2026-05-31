import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import '../services/online_bird_audio_service.dart';
import '../services/online_species_image_service.dart';

class SpeciesInfoSheet extends StatefulWidget {
  final DetectionEvent event;
  final SpeciesProfile profile;
  final bool isLoading;

  const SpeciesInfoSheet({
    super.key,
    required this.event,
    required this.profile,
    required this.isLoading,
  });

  @override
  State<SpeciesInfoSheet> createState() => _SpeciesInfoSheetState();
}

class _SpeciesInfoSheetState extends State<SpeciesInfoSheet> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final OnlineBirdAudioService _birdAudioService = OnlineBirdAudioService();
  final OnlineSpeciesImageService _imageService = OnlineSpeciesImageService();

  bool _isPlaying = false;
  bool _isFindingBirdAudio = false;
  bool _isFindingImage = false;

  String? _audioError;
  String? _currentAudioSourceLabel;
  String? _currentAudioSourceUrl;

  String? _onlineImageUrl;
  String? _onlineDescription;
  String? _onlineImageSourceUrl;

  BirdRecordingResult? _onlineBirdRecording;

  @override
  void initState() {
    super.initState();

    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;

      setState(() {
        _isPlaying = false;
      });
    });

    _loadOnlineImageIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final bool isBat = widget.event.isBat;
    final String? imageUrl = _profileImageUrl(widget.profile) ?? _onlineImageUrl;

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        builder: (BuildContext context, ScrollController scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              if (imageUrl != null && imageUrl.trim().isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.network(
                    imageUrl,
                    height: 250,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _ImageFallback(
                      isBat: isBat,
                      isLoading: _isFindingImage,
                    ),
                  ),
                )
              else
                _ImageFallback(
                  isBat: isBat,
                  isLoading: _isFindingImage,
                ),

              const SizedBox(height: 20),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isBat ? '🦇' : '🐦',
                    style: const TextStyle(fontSize: 42),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.event.commonName,
                          style: const TextStyle(
                            fontSize: 31,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.event.scientificName,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.black54,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              _ConfidenceBand(event: widget.event),

              const SizedBox(height: 18),

              _AudioPanel(
                event: widget.event,
                isPlaying: _isPlaying,
                isFindingBirdAudio: _isFindingBirdAudio,
                audioError: _audioError,
                sourceLabel: _currentAudioSourceLabel,
                sourceUrl: _currentAudioSourceUrl,
                onlineBirdRecording: _onlineBirdRecording,
                onPlay: _handlePlayPressed,
                onFindBirdAudio: _findAndPlayOnlineBirdAudio,
              ),

              const SizedBox(height: 18),

              _InfoCard(
                title: 'About this species',
                body: _profileDescription(widget.profile),
              ),

              if (_onlineImageSourceUrl != null) ...[
                const SizedBox(height: 10),
                _SourceNote(
                  label: 'Image / summary source',
                  value: _onlineImageSourceUrl!,
                ),
              ],

              const SizedBox(height: 14),

              _InfoCard(
                title: 'Habitat notes',
                body: _profileHabitat(widget.profile),
              ),

              const SizedBox(height: 14),

              _InfoCard(
                title: 'Field note',
                body: _fieldNoteText(),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _loadOnlineImageIfNeeded() async {
    final String? existingImage = _profileImageUrl(widget.profile);

    if (existingImage != null && existingImage.trim().isNotEmpty) {
      return;
    }

    if (_isFindingImage) return;

    setState(() {
      _isFindingImage = true;
    });

    try {
      final result = await _imageService.fetchImageAndSummary(
        commonName: widget.event.commonName,
        scientificName: widget.event.scientificName,
      );

      if (!mounted) return;

      setState(() {
        _onlineImageUrl = result?.imageUrl;
        _onlineDescription = result?.description;
        _onlineImageSourceUrl = result?.sourceUrl;
        _isFindingImage = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isFindingImage = false;
      });
    }
  }

  Future<void> _handlePlayPressed() async {
    if (_isPlaying) {
      await _stopAudio();
      return;
    }

    final String? fixedUrl = _profileAudioUrl(widget.profile);

    if (fixedUrl != null && fixedUrl.trim().isNotEmpty) {
      final bool ok = await _tryPlayRemoteUrl(
        url: fixedUrl,
        label: _profileAudioLabel(widget.profile) ??
            'reference wildlife recording',
      );

      if (ok) return;
    }

    if (widget.event.isBird) {
      await _findAndPlayOnlineBirdAudio();
      return;
    }

    setState(() {
      _audioError = 'No playable bat recording is available for this species yet.';
    });
  }

  Future<bool> _tryPlayRemoteUrl({
    required String url,
    required String label,
  }) async {
    try {
      setState(() {
        _audioError = null;
        _currentAudioSourceLabel = label;
        _currentAudioSourceUrl = url;
      });

      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));

      if (!mounted) return false;

      setState(() {
        _isPlaying = true;
      });

      return true;
    } catch (_) {
      if (!mounted) return false;

      setState(() {
        _isPlaying = false;
        _audioError =
            'Reference recording could not be played directly. Trying online bird search if available...';
      });

      return false;
    }
  }

  Future<void> _findAndPlayOnlineBirdAudio() async {
    if (!widget.event.isBird) return;
    if (_isFindingBirdAudio) return;

    setState(() {
      _isFindingBirdAudio = true;
      _audioError = null;
    });

    try {
      final BirdRecordingResult? recording =
          await _birdAudioService.findAndCacheBestRecording(
        commonName: widget.event.commonName,
        scientificName: widget.event.scientificName,
      );

      if (!mounted) return;

      if (recording == null) {
        setState(() {
          _isFindingBirdAudio = false;
          _isPlaying = false;
          _audioError =
              'No playable xeno-canto recording was found for this bird.';
        });
        return;
      }

      _onlineBirdRecording = recording;

      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(recording.localFilePath));

      if (!mounted) return;

      setState(() {
        _isFindingBirdAudio = false;
        _isPlaying = true;
        _audioError = null;
        _currentAudioSourceLabel = recording.sourceLabel;
        _currentAudioSourceUrl = recording.pageUrl;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isFindingBirdAudio = false;
        _isPlaying = false;
        _audioError = 'Online bird recording search failed: $e';
      });
    }
  }

  Future<void> _stopAudio() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _isPlaying = false;
    });
  }

  String _fieldNoteText() {
    final String percent = (widget.event.confidence * 100).toStringAsFixed(0);

    if (widget.event.isBat) {
      return 'This bat was reported by the Raspberry Pi night survey with $percent% confidence.';
    }

    return 'This bird was reported by the Raspberry Pi daytime survey with $percent% confidence. If this species is not part of the local reference set, the app can search xeno-canto for a real online recording.';
  }

  String _profileDescription(SpeciesProfile profile) {
    final String? value = _tryReadString(
      profile,
      const [
        'description',
        'about',
        'summary',
      ],
    );

    if (value != null) return value;

    if (_onlineDescription != null && _onlineDescription!.trim().isNotEmpty) {
      return _onlineDescription!;
    }

    return '${widget.event.commonName} is shown here as a detected species from the Park Life Monitor acoustic monitoring system.';
  }

  String _profileHabitat(SpeciesProfile profile) {
    final String? value = _tryReadString(
      profile,
      const [
        'habitatNote',
        'habitat',
      ],
    );

    if (value != null) return value;

    if (widget.event.isBat) {
      return 'Bats are often associated with woodland edges, waterways, old trees, buildings and dusk activity corridors.';
    }

    return 'Bird habitat depends on the species, but many detected birds are associated with woodland, gardens, parks, grassland, wetlands or urban green spaces.';
  }

  String? _profileImageUrl(SpeciesProfile profile) {
    return _tryReadString(
      profile,
      const [
        'imageUrl',
        'image',
        'photoUrl',
      ],
    );
  }

  String? _profileAudioUrl(SpeciesProfile profile) {
    return _tryReadString(
      profile,
      const [
        'audioUrl',
        'soundUrl',
        'recordingUrl',
      ],
    );
  }

  String? _profileAudioLabel(SpeciesProfile profile) {
    return _tryReadString(
      profile,
      const [
        'audioSource',
        'audioSourceLabel',
        'soundSource',
      ],
    );
  }

  String? _tryReadString(
    SpeciesProfile profile,
    List<String> fieldNames,
  ) {
    final dynamic value = profile;

    for (final String fieldName in fieldNames) {
      try {
        final String? result = _readKnownProfileField(value, fieldName);

        if (result != null && result.trim().isNotEmpty) {
          return result.trim();
        }
      } catch (_) {}
    }

    return null;
  }

  String? _readKnownProfileField(dynamic profile, String fieldName) {
    switch (fieldName) {
      case 'description':
        return profile.description?.toString();
      case 'about':
        return profile.about?.toString();
      case 'summary':
        return profile.summary?.toString();
      case 'habitatNote':
        return profile.habitatNote?.toString();
      case 'habitat':
        return profile.habitat?.toString();
      case 'imageUrl':
        return profile.imageUrl?.toString();
      case 'image':
        return profile.image?.toString();
      case 'photoUrl':
        return profile.photoUrl?.toString();
      case 'audioUrl':
        return profile.audioUrl?.toString();
      case 'soundUrl':
        return profile.soundUrl?.toString();
      case 'recordingUrl':
        return profile.recordingUrl?.toString();
      case 'audioSource':
        return profile.audioSource?.toString();
      case 'audioSourceLabel':
        return profile.audioSourceLabel?.toString();
      case 'soundSource':
        return profile.soundSource?.toString();
      default:
        return null;
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}

class _AudioPanel extends StatelessWidget {
  final DetectionEvent event;
  final bool isPlaying;
  final bool isFindingBirdAudio;
  final String? audioError;
  final String? sourceLabel;
  final String? sourceUrl;
  final BirdRecordingResult? onlineBirdRecording;
  final VoidCallback onPlay;
  final VoidCallback onFindBirdAudio;

  const _AudioPanel({
    required this.event,
    required this.isPlaying,
    required this.isFindingBirdAudio,
    required this.audioError,
    required this.sourceLabel,
    required this.sourceUrl,
    required this.onlineBirdRecording,
    required this.onPlay,
    required this.onFindBirdAudio,
  });

  @override
  Widget build(BuildContext context) {
    final bool isBird = event.isBird;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8E8D2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isBird ? 'Real bird recording' : 'Real bat recording',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isBird
                ? 'The app can search xeno-canto online and cache a real recording for this detected bird.'
                : 'Bat recordings use selected verified sources when available.',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: isFindingBirdAudio ? null : onPlay,
            icon: isFindingBirdAudio
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
            label: Text(
              isFindingBirdAudio
                  ? 'Finding real recording...'
                  : isPlaying
                      ? 'Stop recording'
                      : isBird
                          ? 'Find / play real bird recording'
                          : 'Play real bat recording',
            ),
          ),
          if (isBird) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: isFindingBirdAudio ? null : onFindBirdAudio,
              icon: const Icon(Icons.travel_explore_rounded),
              label: const Text('Search xeno-canto again'),
            ),
          ],
          if (audioError != null) ...[
            const SizedBox(height: 12),
            Text(
              audioError!,
              style: const TextStyle(
                color: Color(0xFFC24B35),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (sourceLabel != null || sourceUrl != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Audio source',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (sourceLabel != null)
                    Text(
                      sourceLabel!,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  if (sourceUrl != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      sourceUrl!,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (onlineBirdRecording != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Cached file: ${File(onlineBirdRecording!.localFilePath).uri.pathSegments.last}',
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfidenceBand extends StatelessWidget {
  final DetectionEvent event;

  const _ConfidenceBand({
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    final String percent = (event.confidence * 100).toStringAsFixed(0);

    Color background;
    Color foreground;
    IconData icon;
    String label;

    if (event.confidence >= 0.75) {
      background = const Color(0xFFE2F7E7);
      foreground = const Color(0xFF26723A);
      icon = Icons.verified_rounded;
      label = 'High confidence';
    } else if (event.confidence >= 0.45) {
      background = const Color(0xFFFFF3C4);
      foreground = const Color(0xFF8A6B00);
      icon = Icons.help_rounded;
      label = 'Possible match';
    } else {
      background = const Color(0xFFFFE4E4);
      foreground = const Color(0xFF9C3535);
      icon = Icons.graphic_eq_rounded;
      label = 'Uncertain signal';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 19),
          const SizedBox(width: 8),
          Text(
            '$label · $percent%',
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
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

class _SourceNote extends StatelessWidget {
  final String label;
  final String value;

  const _SourceNote({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6EF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  final bool isBat;
  final bool isLoading;

  const _ImageFallback({
    required this.isBat,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 230,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isBat
              ? const [
                  Color(0xFF2C2555),
                  Color(0xFF493F78),
                ]
              : const [
                  Color(0xFFDFF2D8),
                  Color(0xFFEAF7FF),
                ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: isLoading
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text(
                    'Finding species image...',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              )
            : Text(
                isBat ? '🦇' : '🐦',
                style: const TextStyle(fontSize: 72),
              ),
      ),
    );
  }
}