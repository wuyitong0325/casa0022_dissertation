import 'package:flutter/material.dart';

class ModeStatusCard extends StatelessWidget {
  final String mode;
  final bool isConnected;
  final String birdStatus;
  final String batStatus;

  const ModeStatusCard({
    super.key,
    required this.mode,
    required this.isConnected,
    required this.birdStatus,
    required this.batStatus,
  });

  @override
  Widget build(BuildContext context) {
    final isBird = mode == 'bird';
    final isBat = mode == 'bat';

    final icon = isBird
        ? '🐦'
        : isBat
            ? '🦇'
            : '🌿';

    final title = isBird
        ? 'Day survey · Bird Mode'
        : isBat
            ? 'Night survey · Bat Mode'
            : 'Waiting for device mode';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isBat
              ? [
                  const Color(0xFF151B33),
                  const Color(0xFF29355F),
                ]
              : [
                  const Color(0xFFE8F7E6),
                  const Color(0xFFD8EEF8),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
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
          Text(icon, style: const TextStyle(fontSize: 50)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isBat ? Colors.white : Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isConnected
                      ? 'Raspberry Pi is listening to the park soundscape.'
                      : 'Waiting for MQTT connection...',
                  style: TextStyle(
                    color: isBat ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Badge(
                      text: isConnected ? 'MQTT online' : 'MQTT offline',
                      color: isConnected ? Colors.green : Colors.red,
                    ),
                    _Badge(text: 'bird: $birdStatus', color: Colors.teal),
                    _Badge(text: 'bat: $batStatus', color: Colors.deepPurple),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}