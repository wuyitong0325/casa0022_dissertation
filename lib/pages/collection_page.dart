import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import '../services/collection_service.dart';
import '../services/detection_history_service.dart';
import '../services/mqtt_service.dart';
import '../services/online_species_service.dart';
import '../services/species_repository.dart';
import '../widgets/species_info_sheet.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  String filter = 'all';
  String? loadingKey;

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();
    final collection = context.watch<CollectionService>();
    final history = context.watch<DetectionHistoryService>();

    final allProfiles = _buildProfileList(mqtt, history.events);
    final stats = _buildStats(history.events);

    final unlockedProfiles = allProfiles.where((profile) {
      final event = _fakeEvent(profile);
      final key = event.speciesKey;
      return collection.isUnlocked(key) || stats.containsKey(key);
    }).toList();

    final birdUnlocked = unlockedProfiles.where((p) => p.type == 'bird').length;
    final batUnlocked = unlockedProfiles.where((p) => p.type == 'bat').length;

    final filtered = allProfiles.where((profile) {
      final event = _fakeEvent(profile);
      final key = event.speciesKey;

      final unlocked = collection.isUnlocked(key) || stats.containsKey(key);
      final favourite = collection.isFavourite(key);

      if (filter == 'birds') return profile.type == 'bird';
      if (filter == 'bats') return profile.type == 'bat';
      if (filter == 'unlocked') return unlocked;
      if (filter == 'locked') return !unlocked;
      if (filter == 'favourites') return favourite;

      return true;
    }).toList();

    filtered.sort((a, b) {
      final aKey = _fakeEvent(a).speciesKey;
      final bKey = _fakeEvent(b).speciesKey;

      final aUnlocked = collection.isUnlocked(aKey) || stats.containsKey(aKey);
      final bUnlocked = collection.isUnlocked(bKey) || stats.containsKey(bKey);

      if (aUnlocked && !bUnlocked) return -1;
      if (!aUnlocked && bUnlocked) return 1;

      return a.commonName.compareTo(b.commonName);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discoveries'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Discovery Collection',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'This page aggregates saved detections by species. Diary shows each event; Discoveries shows what the park has revealed.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          _ProgressPanel(
            discovered: unlockedProfiles.length,
            total: allProfiles.length,
            birds: birdUnlocked,
            bats: batUnlocked,
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
                label: 'Locked',
                value: 'locked',
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
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No species in this filter yet.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ),
          for (final profile in filtered)
            Builder(
              builder: (context) {
                final event = _fakeEvent(profile);
                final key = event.speciesKey;

                final unlocked =
                    collection.isUnlocked(key) || stats.containsKey(key);
                final favourite = collection.isFavourite(key);
                final stat = stats[key];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DiscoveryCard(
                    profile: profile,
                    event: event,
                    unlocked: unlocked,
                    favourite: favourite,
                    stat: stat,
                    isLoading: loadingKey == key,
                    onFavourite: unlocked
                        ? () => collection.toggleFavourite(key)
                        : null,
                    onOpen: unlocked
                        ? () => _openDiscoveryProfile(
                              context: context,
                              profile: profile,
                              event: event,
                            )
                        : null,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  List<SpeciesProfile> _buildProfileList(
    MqttService mqtt,
    List<DetectionEvent> savedEvents,
  ) {
    final profiles = <SpeciesProfile>[
      ...SpeciesRepository.curatedProfiles,
    ];

    for (final onlineProfile in mqtt.speciesProfiles.values) {
      final exists = profiles.any(
        (p) =>
            p.commonName.toLowerCase() ==
                onlineProfile.commonName.toLowerCase() ||
            p.scientificName.toLowerCase() ==
                onlineProfile.scientificName.toLowerCase(),
      );

      if (!exists) {
        profiles.add(onlineProfile);
      }
    }

    for (final event in savedEvents) {
      final profile = mqtt.speciesProfiles[event.speciesKey] ??
          SpeciesRepository.findLocalProfile(event);

      final exists = profiles.any(
        (p) =>
            p.commonName.toLowerCase() == profile.commonName.toLowerCase() ||
            p.scientificName.toLowerCase() ==
                profile.scientificName.toLowerCase(),
      );

      if (!exists) {
        profiles.add(profile);
      }
    }

    return profiles;
  }

  DetectionEvent _fakeEvent(SpeciesProfile profile) {
    return DetectionEvent(
      deviceId: 'discoveries',
      type: profile.type,
      commonName: profile.commonName,
      scientificName: profile.scientificName,
      confidence: 1,
      startTime: 0,
      endTime: 0,
      timestamp: DateTime.now(),
    );
  }

  Map<String, _DiscoveryStats> _buildStats(List<DetectionEvent> events) {
    final map = <String, _DiscoveryStats>{};

    for (final event in events) {
      final key = event.speciesKey;
      final existing = map[key];

      if (existing == null) {
        map[key] = _DiscoveryStats(
          count: 1,
          bestConfidence: event.confidence,
          firstSeen: event.timestamp,
          lastSeen: event.timestamp,
          morningCount: _isMorning(event.timestamp) ? 1 : 0,
          dayCount: _isDay(event.timestamp) ? 1 : 0,
          nightCount: _isNight(event.timestamp) ? 1 : 0,
        );
      } else {
        map[key] = existing.copyWith(
          count: existing.count + 1,
          bestConfidence: event.confidence > existing.bestConfidence
              ? event.confidence
              : existing.bestConfidence,
          firstSeen: event.timestamp.isBefore(existing.firstSeen)
              ? event.timestamp
              : existing.firstSeen,
          lastSeen: event.timestamp.isAfter(existing.lastSeen)
              ? event.timestamp
              : existing.lastSeen,
          morningCount:
              existing.morningCount + (_isMorning(event.timestamp) ? 1 : 0),
          dayCount: existing.dayCount + (_isDay(event.timestamp) ? 1 : 0),
          nightCount: existing.nightCount + (_isNight(event.timestamp) ? 1 : 0),
        );
      }
    }

    return map;
  }

  bool _isMorning(DateTime time) {
    return time.hour >= 5 && time.hour < 11;
  }

  bool _isDay(DateTime time) {
    return time.hour >= 11 && time.hour < 20;
  }

  bool _isNight(DateTime time) {
    return time.hour >= 20 || time.hour < 5;
  }

  Future<void> _openDiscoveryProfile({
    required BuildContext context,
    required SpeciesProfile profile,
    required DetectionEvent event,
  }) async {
    final onlineService = context.read<OnlineSpeciesService>();
    final mqtt = context.read<MqttService>();

    setState(() {
      loadingKey = event.speciesKey;
    });

    SpeciesProfile loadedProfile = mqtt.speciesProfiles[event.speciesKey] ??
        profile;

    try {
      loadedProfile = await onlineService.fetchProfile(event);
      mqtt.speciesProfiles[event.speciesKey] = loadedProfile;
    } catch (_) {
      loadedProfile = mqtt.speciesProfiles[event.speciesKey] ?? profile;
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
        profile: loadedProfile,
        isLoading: false,
      ),
    );
  }

  void _setFilter(String value) {
    setState(() => filter = value);
  }
}

class _ProgressPanel extends StatelessWidget {
  final int discovered;
  final int total;
  final int birds;
  final int bats;

  const _ProgressPanel({
    required this.discovered,
    required this.total,
    required this.birds,
    required this.bats,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : discovered / total;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFE8F7E6),
            Color(0xFFDCEEFF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Park discovery progress',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$discovered of $total species unlocked',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: '✨',
                  value: discovered.toString(),
                  label: 'Unlocked',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  icon: '🐦',
                  value: birds.toString(),
                  label: 'Birds',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  icon: '🦇',
                  value: bats.toString(),
                  label: 'Bats',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String icon;
  final String value;
  final String label;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 27)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
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

class _DiscoveryCard extends StatelessWidget {
  final SpeciesProfile profile;
  final DetectionEvent event;
  final bool unlocked;
  final bool favourite;
  final _DiscoveryStats? stat;
  final bool isLoading;
  final VoidCallback? onFavourite;
  final VoidCallback? onOpen;

  const _DiscoveryCard({
    required this.profile,
    required this.event,
    required this.unlocked,
    required this.favourite,
    required this.stat,
    required this.isLoading,
    required this.onFavourite,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final emoji = profile.type == 'bat' ? '🦇' : '🐦';

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: unlocked ? Colors.white : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: unlocked ? const Color(0xFFB7D9B8) : Colors.black12,
          ),
          boxShadow: unlocked
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: unlocked
                    ? const Color(0xFFEAF6E8)
                    : const Color(0xFFE1E1E1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  unlocked ? emoji : '❔',
                  style: const TextStyle(fontSize: 32),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unlocked ? profile.commonName : _lockedName(profile),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    unlocked ? profile.scientificName : _lockedHint(profile),
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 9),
                  if (unlocked && stat != null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TinyBadge(text: '${stat!.count} detections'),
                        _TinyBadge(
                          text:
                              'best ${(stat!.bestConfidence * 100).toStringAsFixed(0)}%',
                        ),
                        _TinyBadge(text: stat!.activityLabel),
                        _TinyBadge(text: 'last ${_timeText(stat!.lastSeen)}'),
                      ],
                    )
                  else if (unlocked)
                    const _TinyBadge(text: 'Unlocked')
                  else
                    _TinyBadge(
                      text: profile.type == 'bat'
                          ? 'Hint: night survey'
                          : 'Hint: daytime survey',
                    ),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                onPressed: onFavourite,
                icon: Icon(
                  favourite ? Icons.favorite_rounded : Icons.favorite_border,
                  color: favourite ? Colors.red : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _lockedName(SpeciesProfile profile) {
    if (profile.type == 'bat') return 'Hidden bat species';
    return 'Hidden bird species';
  }

  String _lockedHint(SpeciesProfile profile) {
    if (profile.type == 'bat') {
      return 'Listen at night to reveal this ultrasonic visitor.';
    }

    return 'Listen during the day to reveal this park bird.';
  }

  String _timeText(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _TinyBadge extends StatelessWidget {
  final String text;

  const _TinyBadge({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6E8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF357A38),
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
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

class _DiscoveryStats {
  final int count;
  final double bestConfidence;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int morningCount;
  final int dayCount;
  final int nightCount;

  const _DiscoveryStats({
    required this.count,
    required this.bestConfidence,
    required this.firstSeen,
    required this.lastSeen,
    required this.morningCount,
    required this.dayCount,
    required this.nightCount,
  });

  String get activityLabel {
    if (nightCount >= morningCount && nightCount >= dayCount) {
      return 'mostly night';
    }

    if (morningCount >= dayCount && morningCount >= nightCount) {
      return 'mostly morning';
    }

    return 'mostly daytime';
  }

  _DiscoveryStats copyWith({
    int? count,
    double? bestConfidence,
    DateTime? firstSeen,
    DateTime? lastSeen,
    int? morningCount,
    int? dayCount,
    int? nightCount,
  }) {
    return _DiscoveryStats(
      count: count ?? this.count,
      bestConfidence: bestConfidence ?? this.bestConfidence,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      morningCount: morningCount ?? this.morningCount,
      dayCount: dayCount ?? this.dayCount,
      nightCount: nightCount ?? this.nightCount,
    );
  }
}