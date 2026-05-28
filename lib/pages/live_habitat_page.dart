import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/detection_event.dart';
import '../services/mqtt_service.dart';
import '../widgets/detection_celebration_overlay.dart';
import '../widgets/latest_detection_card.dart';
import '../widgets/mode_status_card.dart';
import '../widgets/sound_wave_widget.dart';

class LiveHabitatPage extends StatefulWidget {
  const LiveHabitatPage({super.key});

  @override
  State<LiveHabitatPage> createState() => _LiveHabitatPageState();
}

class _LiveHabitatPageState extends State<LiveHabitatPage> {
  int _lastCelebrationTrigger = -1;
  OverlayEntry? _activeOverlay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final mqtt = context.watch<MqttService>();

    if (mqtt.latestEvent != null &&
        mqtt.animationTrigger != _lastCelebrationTrigger) {
      _lastCelebrationTrigger = mqtt.animationTrigger;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showCelebration(mqtt.latestEvent!);
      });
    }
  }

  void _showCelebration(DetectionEvent event) {
    _activeOverlay?.remove();
    _activeOverlay = null;

    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => DetectionCelebrationOverlay(
        event: event,
        onFinished: () {
          entry.remove();
          if (_activeOverlay == entry) {
            _activeOverlay = null;
          }
        },
      ),
    );

    _activeOverlay = entry;
    Overlay.of(context).insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();

    final latest = mqtt.latestEvent;
    final profile = latest == null ? null : mqtt.profileForEvent(latest);
    final isLoading = latest != null && mqtt.isProfileLoading(latest);

    final isBatMode = mqtt.currentMode == 'bat';

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isBatMode
                    ? [
                        const Color(0xFF0E1733),
                        const Color(0xFF1D2D5C),
                        const Color(0xFF39476F),
                      ]
                    : [
                        const Color(0xFFDFF2D8),
                        const Color(0xFFEAF7FF),
                        const Color(0xFFF8F3E8),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          Positioned(
            right: 24,
            top: 80,
            child: Text(
              isBatMode ? '🌙' : '☀️',
              style: TextStyle(
                fontSize: 74,
                color: Colors.white.withOpacity(0.2),
              ),
            ),
          ),

          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Park Life Monitor',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: isBatMode ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: mqtt.reconnect,
                      icon: const Icon(Icons.sync_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Live bird and bat monitoring in Queen Elizabeth Olympic Park',
                  style: TextStyle(
                    color: isBatMode ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                ModeStatusCard(
                  mode: mqtt.currentMode,
                  isConnected: mqtt.isConnected,
                  birdStatus: mqtt.birdStatus,
                  batStatus: mqtt.batStatus,
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    children: [
                      Text(
                        isBatMode
                            ? 'Listening for ultrasonic night activity'
                            : 'Listening for daytime bird calls',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SoundWaveWidget(
                        active: mqtt.isConnected,
                        intensity: isBatMode ? 1.25 : 0.9,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                LatestDetectionCard(
                  event: latest,
                  profile: profile,
                  isLoading: isLoading,
                ),
                const SizedBox(height: 18),
                _InteractionPanel(mqtt: mqtt),
                const SizedBox(height: 18),
                _RawMessagePanel(message: mqtt.lastRawMessage),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _activeOverlay?.remove();
    super.dispose();
  }
}

class _InteractionPanel extends StatelessWidget {
  final MqttService mqtt;

  const _InteractionPanel({
    required this.mqtt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Field interaction',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use demo detections for presentation, or wait for live MQTT messages from the Raspberry Pi.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: mqtt.addTestBirdEvent,
                icon: const Text('🐦'),
                label: const Text('Test bird'),
              ),
              FilledButton.icon(
                onPressed: mqtt.addTestBatEvent,
                icon: const Text('🦇'),
                label: const Text('Test bat'),
              ),
              OutlinedButton.icon(
                onPressed: mqtt.addTestUncertainEvent,
                icon: const Icon(Icons.graphic_eq_rounded),
                label: const Text('Weak signal'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RawMessagePanel extends StatelessWidget {
  final String message;

  const _RawMessagePanel({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
      collapsedBackgroundColor: Colors.white.withOpacity(0.7),
      backgroundColor: Colors.white.withOpacity(0.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      title: const Text(
        'Latest MQTT message',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              message.isEmpty ? 'Waiting for MQTT payload...' : message,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}