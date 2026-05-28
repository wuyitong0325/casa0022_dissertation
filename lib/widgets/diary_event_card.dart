import 'package:flutter/material.dart';

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import 'confidence_chip.dart';
import 'species_info_sheet.dart';

class DiaryEventCard extends StatelessWidget {
  final DetectionEvent event;
  final SpeciesProfile profile;
  final bool isLoading;
  final VoidCallback onReplay;

  const DiaryEventCard({
    super.key,
    required this.event,
    required this.profile,
    required this.isLoading,
    required this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    final time =
        '${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(event.emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(width: 14),
          Expanded(
            child: InkWell(
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
                    event.commonName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$time · ${event.displayType} activity',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  ConfidenceChip(event: event),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onReplay,
            icon: const Icon(Icons.replay_rounded),
            tooltip: 'Replay animation',
          ),
        ],
      ),
    );
  }
}