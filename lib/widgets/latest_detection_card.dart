import 'package:flutter/material.dart';

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import 'confidence_chip.dart';
import 'species_info_sheet.dart';

class LatestDetectionCard extends StatelessWidget {
  final DetectionEvent? event;
  final SpeciesProfile? profile;
  final bool isLoading;

  const LatestDetectionCard({
    super.key,
    required this.event,
    required this.profile,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (event == null || profile == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(26),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No species detected yet',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 19,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'When the Raspberry Pi hears a bird or bat call, the creature will appear here.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () {
        showModalBottomSheet(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => SpeciesInfoSheet(
            event: event!,
            profile: profile!,
            isLoading: isLoading,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.94),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(event!.emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event!.commonName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    event!.scientificName,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ConfidenceChip(event: event!),
                  const SizedBox(height: 10),
                  Text(
                    isLoading
                        ? 'Searching online for image, description and reference sound...'
                        : profile!.funFact,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black87),
                  ),
                ],
              ),
            ),
            const Icon(Icons.expand_more_rounded),
          ],
        ),
      ),
    );
  }
}