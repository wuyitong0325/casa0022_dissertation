import 'dart:math' as math;

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

    final events = history.events.take(50).toList();
    final speciesStats = _buildSpeciesStats(events);
    final summary = _buildSummary(events, speciesStats);
    final hourlyRows = _buildHourlyBuckets(events);
    final confidenceRows = _buildConfidenceBuckets(events);
    final modeRows = _buildModeStatusRows(events);

    final allProfiles = _buildProfileList(mqtt, events);

    final discoveredProfiles = allProfiles.where((profile) {
      final event = _fakeEvent(profile);
      final key = event.speciesKey;
      return speciesStats.containsKey(key) || collection.isUnlocked(key);
    }).toList();

    final filteredProfiles = discoveredProfiles.where((profile) {
      final event = _fakeEvent(profile);
      final key = event.speciesKey;

      if (filter == 'birds') return profile.type == 'bird';
      if (filter == 'bats') return profile.type == 'bat';
      if (filter == 'favourites') return collection.isFavourite(key);

      return true;
    }).toList();

    filteredProfiles.sort((a, b) {
      final aKey = _fakeEvent(a).speciesKey;
      final bKey = _fakeEvent(b).speciesKey;

      final aCount = speciesStats[aKey]?.count ?? 0;
      final bCount = speciesStats[bKey]?.count ?? 0;

      if (aCount != bCount) return bCount.compareTo(aCount);
      return a.commonName.compareTo(b.commonName);
    });

    final speciesChartRows = speciesStats.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discovery'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Park Wildlife Insights',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              events.isEmpty
                  ? 'Waiting for saved detections. Once the Raspberry Pi publishes bird or bat events, this page will turn them into charts.'
                  : 'Charts are generated from the latest ${events.length} saved detections. Diary keeps the event timeline; Discovery summarises the data.',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),

            _ParkInsightAndSpeciesChart(
              summary: summary,
              speciesRows: speciesChartRows,
            ),
            const SizedBox(height: 16),

            _DetectionsOverTimeChart(rows: hourlyRows),
            const SizedBox(height: 16),

            _ConfidenceDistributionChart(rows: confidenceRows),
            const SizedBox(height: 16),

            _ModeStatusChart(
              rows: modeRows,
              events: events,
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Discovered species',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${filteredProfiles.length}',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Species already detected by the park monitor. Tap a card to view details, images and audio where available.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),

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
                  label: 'Favourites',
                  value: 'favourites',
                  group: filter,
                  onTap: _setFilter,
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (filteredProfiles.isEmpty)
              const _EmptyInsightCard()
            else
              for (final profile in filteredProfiles)
                Builder(
                  builder: (context) {
                    final event = _fakeEvent(profile);
                    final key = event.speciesKey;
                    final stat = speciesStats[key];
                    final favourite = collection.isFavourite(key);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _DiscoveredSpeciesCard(
                        profile: profile,
                        event: event,
                        stat: stat,
                        favourite: favourite,
                        isLoading: loadingKey == key,
                        onFavourite: () => collection.toggleFavourite(key),
                        onOpen: () => _openDiscoveryProfile(
                          context: context,
                          profile: profile,
                          event: event,
                        ),
                      ),
                    );
                  },
                ),
          ],
        ),
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
        (profile) =>
            profile.commonName.toLowerCase() ==
                onlineProfile.commonName.toLowerCase() ||
            profile.scientificName.toLowerCase() ==
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
        (profileItem) =>
            profileItem.commonName.toLowerCase() ==
                profile.commonName.toLowerCase() ||
            profileItem.scientificName.toLowerCase() ==
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

  Map<String, _SpeciesInsight> _buildSpeciesStats(List<DetectionEvent> events) {
    final map = <String, _SpeciesInsight>{};

    for (final event in events) {
      final key = event.speciesKey;
      final existing = map[key];

      if (existing == null) {
        map[key] = _SpeciesInsight(
          key: key,
          type: event.type,
          commonName: event.commonName,
          scientificName: event.scientificName,
          count: 1,
          totalConfidence: event.confidence,
          bestConfidence: event.confidence,
          firstSeen: event.timestamp,
          lastSeen: event.timestamp,
        );
      } else {
        map[key] = existing.copyWith(
          count: existing.count + 1,
          totalConfidence: existing.totalConfidence + event.confidence,
          bestConfidence: math.max(existing.bestConfidence, event.confidence),
          firstSeen: event.timestamp.isBefore(existing.firstSeen)
              ? event.timestamp
              : existing.firstSeen,
          lastSeen: event.timestamp.isAfter(existing.lastSeen)
              ? event.timestamp
              : existing.lastSeen,
        );
      }
    }

    return map;
  }

  _InsightSummary _buildSummary(
    List<DetectionEvent> events,
    Map<String, _SpeciesInsight> speciesStats,
  ) {
    final birdCount = events.where((event) => event.isBird).length;
    final batCount = events.where((event) => event.isBat).length;

    final topSpecies = speciesStats.values.isEmpty
        ? null
        : (speciesStats.values.toList()
          ..sort((a, b) => b.count.compareTo(a.count))).first;

    final averageConfidence = events.isEmpty
        ? 0.0
        : events.fold<double>(0.0, (sum, event) => sum + event.confidence) /
            events.length;

    return _InsightSummary(
      totalDetections: events.length,
      speciesCount: speciesStats.length,
      birdDetections: birdCount,
      batDetections: batCount,
      averageConfidence: averageConfidence,
      topSpeciesName: topSpecies?.commonName ?? 'No species yet',
      topSpeciesCount: topSpecies?.count ?? 0,
    );
  }

  List<_HourBucket> _buildHourlyBuckets(List<DetectionEvent> events) {
    final map = <int, _HourBucket>{};

    for (final event in events) {
      final hour = event.timestamp.hour;
      final existing = map[hour];

      if (existing == null) {
        map[hour] = _HourBucket(
          hour: hour,
          birdCount: event.isBird ? 1 : 0,
          batCount: event.isBat ? 1 : 0,
        );
      } else {
        map[hour] = existing.copyWith(
          birdCount: existing.birdCount + (event.isBird ? 1 : 0),
          batCount: existing.batCount + (event.isBat ? 1 : 0),
        );
      }
    }

    return map.values.toList()..sort((a, b) => a.hour.compareTo(b.hour));
  }

  List<_ChartRow> _buildConfidenceBuckets(List<DetectionEvent> events) {
    var high = 0;
    var medium = 0;
    var low = 0;

    for (final event in events) {
      if (event.confidence >= 0.70) {
        high++;
      } else if (event.confidence >= 0.40) {
        medium++;
      } else {
        low++;
      }
    }

    return [
      _ChartRow(label: 'High ≥70%', value: high),
      _ChartRow(label: 'Medium 40–69%', value: medium),
      _ChartRow(label: 'Low <40%', value: low),
    ];
  }

  List<_ChartRow> _buildModeStatusRows(List<DetectionEvent> events) {
    final birds = events.where((event) => event.isBird).length;
    final bats = events.where((event) => event.isBat).length;

    return [
      _ChartRow(label: 'Bird-mode detections', value: birds),
      _ChartRow(label: 'Bat-mode detections', value: bats),
      _ChartRow(label: 'Successful analyses saved', value: events.length),
      _ChartRow(label: 'Timeout / error records', value: 0),
    ];
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

    SpeciesProfile loadedProfile =
        mqtt.speciesProfiles[event.speciesKey] ?? profile;

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
    setState(() {
      filter = value;
    });
  }
}

class _ParkInsightAndSpeciesChart extends StatelessWidget {
  final _InsightSummary summary;
  final List<_SpeciesInsight> speciesRows;

  const _ParkInsightAndSpeciesChart({
    required this.summary,
    required this.speciesRows,
  });

  @override
  Widget build(BuildContext context) {
    final chartRows = speciesRows.take(8).map((species) {
      final icon = species.type == 'bat' ? '🦇' : '🐦';
      return _ChartRow(
        label: '$icon ${species.commonName}',
        value: species.count,
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFE8F7E6),
            Color(0xFFDCEEFF),
            Color(0xFFFFF1D9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Park Wildlife Insight',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            summary.totalDetections == 0
                ? 'No saved detections yet. Start the Raspberry Pi detector to build this insight panel.'
                : 'Top species: ${summary.topSpeciesName} · ${summary.topSpeciesCount} detection${summary.topSpeciesCount == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: '🌿',
                  value: summary.totalDetections.toString(),
                  label: 'Detections',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  icon: '🧬',
                  value: summary.speciesCount.toString(),
                  label: 'Species',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: '🐦',
                  value: summary.birdDetections.toString(),
                  label: 'Bird events',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  icon: '🦇',
                  value: summary.batDetections.toString(),
                  label: 'Bat events',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  icon: '📈',
                  value:
                      '${(summary.averageConfidence * 100).toStringAsFixed(0)}%',
                  label: 'Avg confidence',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Species count',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Most frequently detected species in the saved history.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          chartRows.isEmpty
              ? const _NoDataText()
              : _HorizontalBarChart(
                  rows: chartRows,
                  valueSuffix: ' events',
                ),
        ],
      ),
    );
  }
}

class _DetectionsOverTimeChart extends StatelessWidget {
  final List<_HourBucket> rows;

  const _DetectionsOverTimeChart({
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return _InsightCard(
      title: 'Detections over time',
      subtitle:
          'Saved detections grouped by hour. This can show daytime bird activity and nighttime bat activity.',
      child: rows.isEmpty
          ? const _NoDataText()
          : Column(
              children: [
                SizedBox(
                  height: 170,
                  child: _LineChart(
                    points: rows
                        .map(
                          (row) => _LinePoint(
                            label: '${row.hour.toString().padLeft(2, '0')}:00',
                            value: row.total.toDouble(),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: rows.map((row) {
                    return _TinyBadge(
                      text:
                          '${row.hour.toString().padLeft(2, '0')}:00 · 🐦${row.birdCount} 🦇${row.batCount}',
                    );
                  }).toList(),
                ),
              ],
            ),
    );
  }
}

class _ConfidenceDistributionChart extends StatelessWidget {
  final List<_ChartRow> rows;

  const _ConfidenceDistributionChart({
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return _InsightCard(
      title: 'Confidence distribution',
      subtitle:
          'AI confidence grouped into high, medium and low bands for evaluation reporting.',
      child: _HorizontalBarChart(
        rows: rows,
        valueSuffix: ' detections',
      ),
    );
  }
}

class _ModeStatusChart extends StatelessWidget {
  final List<_ChartRow> rows;
  final List<DetectionEvent> events;

  const _ModeStatusChart({
    required this.rows,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    final latest = events.isEmpty ? null : events.first;

    return _InsightCard(
      title: 'System mode and pipeline status',
      subtitle:
          'A reliability-style chart based on saved detections. True mode running time, MQTT uptime and timeout/error history require saving status events separately.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HorizontalBarChart(
            rows: rows,
            valueSuffix: ' records',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: latest?.isBat == true ? '🦇' : '🐦',
                  value: latest?.displayType ?? 'Waiting',
                  label: 'Latest mode evidence',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  icon: '📡',
                  value: latest == null
                      ? 'No data'
                      : latest.isBat
                          ? 'BatDetect2'
                          : 'Bird detector',
                  label: 'Latest source',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiscoveredSpeciesCard extends StatelessWidget {
  final SpeciesProfile profile;
  final DetectionEvent event;
  final _SpeciesInsight? stat;
  final bool favourite;
  final bool isLoading;
  final VoidCallback onFavourite;
  final VoidCallback onOpen;

  const _DiscoveredSpeciesCard({
    required this.profile,
    required this.event,
    required this.stat,
    required this.favourite,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFB7D9B8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6E8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  emoji,
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
                    profile.commonName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    profile.scientificName,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TinyBadge(text: '${stat?.count ?? 0} detections'),
                      _TinyBadge(
                        text:
                            'avg ${((stat?.averageConfidence ?? 0) * 100).toStringAsFixed(0)}%',
                      ),
                      _TinyBadge(
                        text:
                            'best ${((stat?.bestConfidence ?? 0) * 100).toStringAsFixed(0)}%',
                      ),
                      if (stat != null)
                        _TinyBadge(text: 'last ${_timeText(stat!.lastSeen)}'),
                    ],
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

  String _timeText(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _InsightCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _InsightCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE1E8DF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.black54,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String icon;
  final String value;
  final String label;

  const _MetricTile({
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
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 25)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
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

class _HorizontalBarChart extends StatelessWidget {
  final List<_ChartRow> rows;
  final String valueSuffix;

  const _HorizontalBarChart({
    required this.rows,
    this.valueSuffix = '',
  });

  @override
  Widget build(BuildContext context) {
    final maxValue =
        rows.fold<int>(0, (max, row) => row.value > max ? row.value : max);

    if (rows.isEmpty || maxValue == 0) {
      return const _NoDataText();
    }

    return Column(
      children: rows.map((row) {
        final fraction = maxValue == 0 ? 0.0 : row.value / maxValue;

        return Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '${row.value}$valueSuffix',
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  children: [
                    Container(
                      height: 12,
                      color: const Color(0xFFEAF1E8),
                    ),
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(0.0, 1.0),
                      child: Container(
                        height: 12,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF77B255),
                              Color(0xFF3D8C7B),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _LineChart extends StatelessWidget {
  final List<_LinePoint> points;

  const _LineChart({
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(points: points),
      child: Container(),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_LinePoint> points;

  _LineChartPainter({
    required this.points,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = const Color(0xFFE0E6DD)
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..color = const Color(0xFF357A38)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = const Color(0xFF77B255).withOpacity(0.13)
      ..style = PaintingStyle.fill;

    final dotPaint = Paint()
      ..color = const Color(0xFF357A38)
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    const left = 28.0;
    const right = 10.0;
    const top = 12.0;
    const bottom = 32.0;

    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;

    canvas.drawLine(
      Offset(left, top),
      Offset(left, top + chartHeight),
      axisPaint,
    );

    canvas.drawLine(
      Offset(left, top + chartHeight),
      Offset(left + chartWidth, top + chartHeight),
      axisPaint,
    );

    if (points.isEmpty) return;

    final maxValue = math.max(
      1.0,
      points.fold<double>(0.0, (max, point) => math.max(max, point.value)),
    );

    final offsets = <Offset>[];

    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? left + chartWidth / 2
          : left + chartWidth * (i / (points.length - 1));
      final y = top + chartHeight - (points[i].value / maxValue) * chartHeight;

      offsets.add(Offset(x, y));
    }

    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);

    for (var i = 1; i < offsets.length; i++) {
      path.lineTo(offsets[i].dx, offsets[i].dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(offsets.last.dx, top + chartHeight)
      ..lineTo(offsets.first.dx, top + chartHeight)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    for (final offset in offsets) {
      canvas.drawCircle(offset, 4, dotPaint);
    }

    for (var i = 0; i < points.length; i++) {
      if (points.length > 6 && i.isOdd) continue;

      textPainter.text = TextSpan(
        text: points[i].label,
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      );

      textPainter.layout(maxWidth: 46);

      textPainter.paint(
        canvas,
        Offset(
          offsets[i].dx - textPainter.width / 2,
          top + chartHeight + 8,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points != points;
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

class _NoDataText extends StatelessWidget {
  const _NoDataText();

  @override
  Widget build(BuildContext context) {
    const message = 'No saved detection data yet.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.black54),
      ),
    );
  }
}

class _EmptyInsightCard extends StatelessWidget {
  const _EmptyInsightCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Text(
          'No discovered species yet. Run bird or bat detection to build this section.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      ),
    );
  }
}

class _InsightSummary {
  final int totalDetections;
  final int speciesCount;
  final int birdDetections;
  final int batDetections;
  final double averageConfidence;
  final String topSpeciesName;
  final int topSpeciesCount;

  const _InsightSummary({
    required this.totalDetections,
    required this.speciesCount,
    required this.birdDetections,
    required this.batDetections,
    required this.averageConfidence,
    required this.topSpeciesName,
    required this.topSpeciesCount,
  });
}

class _SpeciesInsight {
  final String key;
  final String type;
  final String commonName;
  final String scientificName;
  final int count;
  final double totalConfidence;
  final double bestConfidence;
  final DateTime firstSeen;
  final DateTime lastSeen;

  const _SpeciesInsight({
    required this.key,
    required this.type,
    required this.commonName,
    required this.scientificName,
    required this.count,
    required this.totalConfidence,
    required this.bestConfidence,
    required this.firstSeen,
    required this.lastSeen,
  });

  double get averageConfidence {
    if (count == 0) return 0.0;
    return totalConfidence / count;
  }

  _SpeciesInsight copyWith({
    int? count,
    double? totalConfidence,
    double? bestConfidence,
    DateTime? firstSeen,
    DateTime? lastSeen,
  }) {
    return _SpeciesInsight(
      key: key,
      type: type,
      commonName: commonName,
      scientificName: scientificName,
      count: count ?? this.count,
      totalConfidence: totalConfidence ?? this.totalConfidence,
      bestConfidence: bestConfidence ?? this.bestConfidence,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

class _HourBucket {
  final int hour;
  final int birdCount;
  final int batCount;

  const _HourBucket({
    required this.hour,
    required this.birdCount,
    required this.batCount,
  });

  int get total => birdCount + batCount;

  _HourBucket copyWith({
    int? birdCount,
    int? batCount,
  }) {
    return _HourBucket(
      hour: hour,
      birdCount: birdCount ?? this.birdCount,
      batCount: batCount ?? this.batCount,
    );
  }
}

class _ChartRow {
  final String label;
  final int value;

  const _ChartRow({
    required this.label,
    required this.value,
  });
}

class _LinePoint {
  final String label;
  final double value;

  const _LinePoint({
    required this.label,
    required this.value,
  });
}