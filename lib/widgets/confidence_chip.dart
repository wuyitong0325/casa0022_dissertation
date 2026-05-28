import 'package:flutter/material.dart';

import '../models/detection_event.dart';

class ConfidenceChip extends StatelessWidget {
  final DetectionEvent event;

  const ConfidenceChip({
    super.key,
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    final confidence = event.confidence;

    Color background;
    Color foreground;
    IconData icon;

    if (confidence >= 0.75) {
      background = const Color(0xFFE5F7EA);
      foreground = const Color(0xFF217A3A);
      icon = Icons.verified_rounded;
    } else if (confidence >= 0.40) {
      background = const Color(0xFFFFF4D8);
      foreground = const Color(0xFF8A6200);
      icon = Icons.help_rounded;
    } else {
      background = const Color(0xFFFFE8E8);
      foreground = const Color(0xFF9B2C2C);
      icon = Icons.graphic_eq_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 6),
          Text(
            '${event.confidenceLabel} · ${event.confidenceText}',
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}