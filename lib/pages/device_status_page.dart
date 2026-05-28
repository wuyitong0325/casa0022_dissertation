import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/mqtt_service.dart';

class DeviceStatusPage extends StatelessWidget {
  const DeviceStatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Status'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusTile(
            icon: Icons.router_rounded,
            title: 'MQTT broker',
            value: mqtt.isConnected
                ? 'Connected'
                : mqtt.isConnecting
                    ? 'Connecting...'
                    : 'Disconnected',
            good: mqtt.isConnected,
          ),
          _StatusTile(
            icon: Icons.memory_rounded,
            title: 'Current mode',
            value: mqtt.currentMode,
            good: mqtt.currentMode != 'unknown',
          ),
          _StatusTile(
            icon: Icons.flutter_dash_rounded,
            title: 'Bird listener',
            value: mqtt.birdStatus,
            good: mqtt.birdStatus != 'waiting',
          ),
          _StatusTile(
            icon: Icons.dark_mode_rounded,
            title: 'Bat listener',
            value: mqtt.batStatus,
            good: mqtt.batStatus != 'waiting',
          ),
          _StatusTile(
            icon: Icons.eco_rounded,
            title: 'Bird detections',
            value: mqtt.birdDetectionCount.toString(),
            good: mqtt.birdDetectionCount > 0,
          ),
          _StatusTile(
            icon: Icons.nightlight_round,
            title: 'Bat detections',
            value: mqtt.batDetectionCount.toString(),
            good: mqtt.batDetectionCount > 0,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: mqtt.reconnect,
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Reconnect MQTT'),
          ),
          const SizedBox(height: 18),
          ExpansionTile(
            title: const Text('Latest raw MQTT payload'),
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    mqtt.lastRawMessage.isEmpty
                        ? 'No MQTT payload received yet.'
                        : mqtt.lastRawMessage,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool good;

  const _StatusTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.good,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        tileColor: Colors.white,
        leading: CircleAvatar(
          backgroundColor:
              good ? const Color(0xFFE1F7E7) : const Color(0xFFFFE8E8),
          child: Icon(
            icon,
            color: good ? Colors.green : Colors.red,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(value),
      ),
    );
  }
}