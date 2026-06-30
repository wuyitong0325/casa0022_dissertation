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

    final width = MediaQuery.of(context).size.width;
    final compact = width < 380;

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
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 16,
                compact ? 10 : 16,
                compact ? 10 : 16,
                24,
              ),
              children: [
                Text(
                  'Field Notes Timeline',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 25 : 28,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Diary records the latest 30 detection events in time order. These notes are saved locally on this phone.',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: compact ? 14 : 15,
                    height: 1.35,
                  ),
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

  void _openDetails(
    BuildContext context,
    DetectionEvent event,
    dynamic profile,
    bool isLoading,
  ) {
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
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();

    final profile = mqtt.profileForEvent(event);
    final isLoading = mqtt.isProfileLoading(event);

    final width = MediaQuery.of(context).size.width;
    final compact = width < 380;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: compact ? 30 : 42,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst ? Colors.transparent : Colors.black12,
                  ),
                ),
                Container(
                  width: compact ? 28 : 34,
                  height: compact ? 28 : 34,
                  decoration: BoxDecoration(
                    color: event.isBat
                        ? const Color(0xFFE8DDFF)
                        : const Color(0xFFE1F7E7),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      event.emoji,
                      style: TextStyle(fontSize: compact ? 17 : 20),
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
          SizedBox(width: compact ? 6 : 10),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: EdgeInsets.all(compact ? 13 : 16),
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
                onTap: () => _openDetails(
                  context,
                  event,
                  profile,
                  isLoading,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _timeText(event.timestamp),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black45,
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 13 : 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      event.isBat
                          ? 'Night bat activity'
                          : 'Daytime bird activity',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: compact ? 16 : 17,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      event.commonName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: compact ? 19 : 20,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      event.scientificName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black54,
                        fontStyle: FontStyle.italic,
                        fontSize: compact ? 14 : 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: ConfidenceChip(event: event),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: compact ? 38 : 40,
                            child: OutlinedButton(
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
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              child: Text(
                                'Replay',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.visible,
                                style: TextStyle(
                                  fontSize: compact ? 12.5 : 13.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: compact ? 38 : 40,
                            child: FilledButton(
                              onPressed: () => _openDetails(
                                context,
                                event,
                                profile,
                                isLoading,
                              ),
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              child: Text(
                                'Details',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.visible,
                                style: TextStyle(
                                  fontSize: compact ? 12.5 : 13.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
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