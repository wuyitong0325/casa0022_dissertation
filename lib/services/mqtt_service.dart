import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import 'collection_service.dart';
import 'mqtt_config.dart';
import 'online_species_service.dart';
import 'species_repository.dart';

class MqttService extends ChangeNotifier {
  final OnlineSpeciesService onlineSpeciesService;
  final CollectionService collectionService;

  MqttServerClient? _client;

  bool isConnected = false;
  bool isConnecting = false;

  String currentMode = 'unknown';
  String birdStatus = 'waiting';
  String batStatus = 'waiting';
  String lastRawMessage = '';

  DetectionEvent? latestEvent;
  DetectionEvent? replayEvent;

  int animationTrigger = 0;

  final List<DetectionEvent> diaryEvents = [];
  final Map<String, SpeciesProfile> speciesProfiles = {};
  final Set<String> loadingSpeciesKeys = {};

  int birdDetectionCount = 0;
  int batDetectionCount = 0;

  MqttService({
    required this.onlineSpeciesService,
    required this.collectionService,
  });

  Future<void> connect() async {
    if (isConnecting) return;

    isConnecting = true;
    notifyListeners();

    final clientId =
        'park-life-monitor-app-${DateTime.now().millisecondsSinceEpoch}';

    _client = MqttServerClient(AppMqttConfig.broker, clientId);
    _client!.port = AppMqttConfig.port;
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 20;
    _client!.autoReconnect = true;
    _client!.secure = false;

    _client!.onConnected = _onConnected;
    _client!.onDisconnected = _onDisconnected;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(AppMqttConfig.username, AppMqttConfig.password)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    _client!.connectionMessage = connMessage;

    try {
      await _client!.connect();
    } catch (e) {
      debugPrint('MQTT connection failed: $e');
      _client?.disconnect();
      isConnected = false;
      isConnecting = false;
      notifyListeners();
      return;
    }

    isConnecting = false;

    if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
      isConnected = true;

      _client!.subscribe(AppMqttConfig.subscribeTopic, MqttQos.atLeastOnce);

      _client!.updates?.listen(_handleMessages);

      debugPrint(
        'MQTT connected and subscribed to ${AppMqttConfig.subscribeTopic}',
      );
    } else {
      debugPrint('MQTT connection failed: ${_client!.connectionStatus}');
      isConnected = false;
    }

    notifyListeners();
  }

  void _handleMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    final receivedTopic = messages[0].topic;
    final receivedMessage = messages[0].payload as MqttPublishMessage;

    final payload = MqttPublishPayload.bytesToStringAsString(
      receivedMessage.payload.message,
    );

    lastRawMessage = '[$receivedTopic] $payload';
    debugPrint('MQTT received: $lastRawMessage');

    try {
      final jsonMap = jsonDecode(payload) as Map<String, dynamic>;

      if (receivedTopic == AppMqttConfig.modeTopic) {
        currentMode = jsonMap['mode']?.toString() ?? 'unknown';
        notifyListeners();
        return;
      }

      if (receivedTopic == AppMqttConfig.birdStatusTopic) {
        birdStatus = jsonMap['status']?.toString() ?? 'unknown';
        notifyListeners();
        return;
      }

      if (receivedTopic == AppMqttConfig.batStatusTopic) {
        batStatus = jsonMap['status']?.toString() ?? 'unknown';
        notifyListeners();
        return;
      }

      if (receivedTopic == AppMqttConfig.birdDetectionTopic ||
          receivedTopic == AppMqttConfig.batDetectionTopic ||
          receivedTopic.startsWith('${AppMqttConfig.baseTopic}/detections/')) {
        final event = DetectionEvent.fromJson(jsonMap);
        _processDetection(event);
        return;
      }
    } catch (e) {
      debugPrint('Failed to parse MQTT payload: $e');
    }

    notifyListeners();
  }

  void _processDetection(DetectionEvent event) {
    latestEvent = event;
    replayEvent = event;
    animationTrigger++;

    diaryEvents.insert(0, event);

    if (diaryEvents.length > 200) {
      diaryEvents.removeLast();
    }

    if (event.isBird) {
      birdDetectionCount++;
      birdStatus = 'bird_detected';
    }

    if (event.isBat) {
      batDetectionCount++;
      batStatus = 'bat_detected';
    }

    collectionService.unlockFromEvent(event);

    speciesProfiles[event.speciesKey] =
        SpeciesRepository.findLocalProfile(event);

    notifyListeners();

    _loadOnlineProfile(event);
  }

  Future<void> _loadOnlineProfile(DetectionEvent event) async {
    final key = event.speciesKey;

    if (loadingSpeciesKeys.contains(key)) return;

    loadingSpeciesKeys.add(key);
    notifyListeners();

    try {
      final profile = await onlineSpeciesService.fetchProfile(event);
      speciesProfiles[key] = profile;
    } catch (e) {
      debugPrint('Online species profile failed: $e');
    } finally {
      loadingSpeciesKeys.remove(key);
      notifyListeners();
    }
  }

  SpeciesProfile profileForEvent(DetectionEvent event) {
    return speciesProfiles[event.speciesKey] ??
        SpeciesRepository.findLocalProfile(event);
  }

  bool isProfileLoading(DetectionEvent event) {
    return loadingSpeciesKeys.contains(event.speciesKey);
  }

  void replayDetection(DetectionEvent event) {
    replayEvent = event;
    animationTrigger++;
    notifyListeners();
  }

  Future<bool> publishModeCommand(String mode) async {
    final normalisedMode = mode.toLowerCase().trim();

    if (!['bird', 'bat', 'stop'].contains(normalisedMode)) {
      debugPrint('Invalid exhibition mode command: $mode');
      return false;
    }

    final client = _client;

    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      debugPrint('Cannot publish exhibition command. MQTT is not connected.');
      lastRawMessage =
          '[COMMAND FAILED] MQTT not connected. Tried to send: $normalisedMode';
      notifyListeners();
      return false;
    }

    final topic = '${AppMqttConfig.baseTopic}/command/mode';
    final builder = MqttClientPayloadBuilder();
    builder.addString(normalisedMode);

    try {
      client.publishMessage(
        topic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      lastRawMessage = '[COMMAND -> $topic] $normalisedMode';

      if (normalisedMode == 'bird') {
        currentMode = 'bird';
      } else if (normalisedMode == 'bat') {
        currentMode = 'bat';
      } else if (normalisedMode == 'stop') {
        currentMode = 'none';
      }

      debugPrint('Published exhibition mode command: $normalisedMode');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to publish exhibition command: $e');
      lastRawMessage = '[COMMAND ERROR] $e';
      notifyListeners();
      return false;
    }
  }

  void _onConnected() {
    debugPrint('MQTT connected');
    isConnected = true;
    isConnecting = false;
    notifyListeners();
  }

  void _onDisconnected() {
    debugPrint('MQTT disconnected');
    isConnected = false;
    isConnecting = false;
    notifyListeners();
  }

  Future<void> reconnect() async {
    disconnect();
    await Future.delayed(const Duration(seconds: 1));
    await connect();
  }

  void disconnect() {
    _client?.disconnect();
    isConnected = false;
    notifyListeners();
  }

  void clearDiary() {
    diaryEvents.clear();
    latestEvent = null;
    replayEvent = null;
    birdDetectionCount = 0;
    batDetectionCount = 0;
    notifyListeners();
  }

  void addTestBirdEvent() {
    final event = DetectionEvent(
      deviceId: 'test-device',
      type: 'bird',
      commonName: 'Common Raven',
      scientificName: 'Corvus corax',
      confidence: 0.87,
      startTime: 0,
      endTime: 3,
      timestamp: DateTime.now(),
    );

    _processDetection(event);
  }

  void addTestBatEvent() {
    final event = DetectionEvent(
      deviceId: 'test-device',
      type: 'bat',
      commonName: 'Common Pipistrelle',
      scientificName: 'Pipistrellus pipistrellus',
      confidence: 0.91,
      startTime: 0,
      endTime: 3,
      timestamp: DateTime.now(),
    );

    _processDetection(event);
  }

  void addTestUncertainEvent() {
    final event = DetectionEvent(
      deviceId: 'test-device',
      type: 'bird',
      commonName: 'Weak acoustic pattern',
      scientificName: 'Unknown',
      confidence: 0.18,
      startTime: 0,
      endTime: 3,
      timestamp: DateTime.now(),
    );

    _processDetection(event);
  }
}