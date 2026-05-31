import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/detection_event.dart';
import '../services/detection_history_service.dart';
import '../services/mqtt_service.dart';
import '../widgets/confidence_chip.dart';
import '../widgets/species_info_sheet.dart';

class NatureDiaryPage extends StatelessWidget {
  const NatureDiaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<DetectionHistoryService>();
    final events = history.events;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nature Diary'),
        actions: [
          IconButton(
            onPressed: events.isEmpty ? null : history.clear,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear diary',
          ),
        ],
      ),
      body: events.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'No field notes yet.\nLive bird and bat detections will appear here and stay saved after closing the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Field Notes Timeline',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Diary records the latest 30 detection events in time order. These notes are saved locally on this phone.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 18),
                for (int i = 0; i < events.length; i++)
                  _TimelineEntry(
                    event: events[i],
                    isFirst: i == 0,
                    isLast: i == events.length - 1,
                  ),
              ],
            ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final DetectionEvent event;
  final bool isFirst;
  final bool isLast;

  const _TimelineEntry({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();

    final profile = mqtt.profileForEvent(event);
    final isLoading = mqtt.isProfileLoading(event);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 42,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst ? Colors.transparent : Colors.black12,
                  ),
                ),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: event.isBat
                        ? const Color(0xFFE8DDFF)
                        : const Color(0xFFE1F7E7),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      event.emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : Colors.black12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) => SpeciesInfoSheet(
                      event: event,
                      profile: profile,
                      isLoading: isLoading,
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _timeText(event.timestamp),
                      style: const TextStyle(
                        color: Colors.black45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      event.isBat
                          ? 'Night bat activity'
                          : 'Daytime bird activity',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      event.commonName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      event.scientificName,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConfidenceChip(event: event),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              mqtt.replayDetection(event);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Animation replayed on the Live page.',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.replay_rounded),
                            label: const Text('Replay'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                showDragHandle: true,
                                isScrollControlled: true,
                                builder: (_) => SpeciesInfoSheet(
                                  event: event,
                                  profile: profile,
                                  isLoading: isLoading,
                                ),
                              );
                            },
                            icon: const Icon(Icons.info_outline_rounded),
                            label: const Text('Details'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timeText(DateTime time) {
    final date =
        '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

    return '$date · $clock';
  }
}