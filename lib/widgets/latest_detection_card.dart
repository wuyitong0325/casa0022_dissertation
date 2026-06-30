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
    final width = MediaQuery.of(context).size.width;
    final compact = width < 380;

    if (event == null || profile == null) {
      return Container(
        padding: EdgeInsets.all(compact ? 16 : 20),
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
              style: TextStyle(
                color: Colors.black54,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    final detection = event!;
    final speciesProfile = profile!;

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () {
        showModalBottomSheet(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => SpeciesInfoSheet(
            event: detection,
            profile: speciesProfile,
            isLoading: isLoading,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 15 : 18),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: compact ? 50 : 58,
              child: Center(
                child: Text(
                  detection.emoji,
                  style: TextStyle(fontSize: compact ? 42 : 52),
                ),
              ),
            ),

            SizedBox(width: compact ? 10 : 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detection.commonName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 19 : 21,
                      height: 1.08,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    detection.scientificName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      color: Colors.black54,
                      fontStyle: FontStyle.italic,
                      fontSize: compact ? 14 : 15,
                    ),
                  ),

                  const SizedBox(height: 9),

                  // 关键修复：ConfidenceChip 在窄屏上不能继续撑爆 Row。
                  // FittedBox 会在必要时把 chip 缩小一点，而不是 overflow。
                  SizedBox(
                    width: double.infinity,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: ConfidenceChip(event: detection),
                      ),
                    ),
                  ),

                  const SizedBox(height: 9),

                  Text(
                    isLoading
                        ? 'Searching online for image, description and reference sound...'
                        : speciesProfile.funFact,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: compact ? 14 : 15,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 4),

            const Padding(
              padding: EdgeInsets.only(top: 26),
              child: Icon(
                Icons.expand_more_rounded,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}