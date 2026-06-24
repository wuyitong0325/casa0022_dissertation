import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/mqtt_service.dart';

class DeviceStatusPage extends StatelessWidget {
  const DeviceStatusPage({super.key});

  Future<void> _sendModeCommand(
    BuildContext context,
    MqttService mqtt,
    String mode,
    String label,
  ) async {
    final success = await mqtt.publishModeCommand(mode);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '$label command sent to Raspberry Pi.'
              : 'Failed to send $label command. Check MQTT connection.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

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
          _ExhibitionControlCard(
            mqtt: mqtt,
            onSendCommand: _sendModeCommand,
          ),
          const SizedBox(height: 16),
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

class _ExhibitionControlCard extends StatelessWidget {
  final MqttService mqtt;
  final Future<void> Function(
    BuildContext context,
    MqttService mqtt,
    String mode,
    String label,
  ) onSendCommand;

  const _ExhibitionControlCard({
    required this.mqtt,
    required this.onSendCommand,
  });

  @override
  Widget build(BuildContext context) {
    final connected = mqtt.isConnected;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: connected
              ? const Color(0xFFCBE8C9)
              : const Color(0xFFFFD2D2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: connected
                    ? const Color(0xFFE1F7E7)
                    : const Color(0xFFFFE8E8),
                child: Icon(
                  Icons.tune_rounded,
                  color: connected ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Exhibition Manual Control',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Manually switch the Raspberry Pi between bird and bat detection.',
                      style: TextStyle(
                        color: Colors.black54,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F9F3),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              'Current mode: ${mqtt.currentMode}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: connected
                      ? () => onSendCommand(
                            context,
                            mqtt,
                            'bird',
                            'Bird mode',
                          )
                      : null,
                  icon: const Icon(Icons.flutter_dash_rounded),
                  label: const Text('Bird'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: connected
                      ? () => onSendCommand(
                            context,
                            mqtt,
                            'bat',
                            'Bat mode',
                          )
                      : null,
                  icon: const Icon(Icons.nightlight_round),
                  label: const Text('Bat'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: connected
                  ? () => onSendCommand(
                        context,
                        mqtt,
                        'stop',
                        'Stop detection',
                      )
                  : null,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Stop detection'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'These buttons publish bird / bat / stop commands to the exhibition controller on the Raspberry Pi. Detection results are still shown through the normal live MQTT detection topics.',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 12,
              height: 1.35,
            ),
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