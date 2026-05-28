import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/mqtt_service.dart';
import '../widgets/diary_event_card.dart';

class NatureDiaryPage extends StatelessWidget {
  const NatureDiaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();

    final events = mqtt.diaryEvents;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nature Diary'),
        actions: [
          IconButton(
            onPressed: mqtt.clearDiary,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: events.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'No diary entries yet.\nLive detections will become field notes here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final event = events[index];

                return DiaryEventCard(
                  event: event,
                  profile: mqtt.profileForEvent(event),
                  isLoading: mqtt.isProfileLoading(event),
                  onReplay: () {
                    mqtt.replayDetection(event);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Animation replayed on the Live Habitat page.',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}