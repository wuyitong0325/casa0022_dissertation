import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/detection_event.dart';

import 'pages/collection_page.dart';
import 'pages/device_status_page.dart';
import 'pages/live_habitat_page.dart';
import 'pages/nature_diary_page.dart';
import 'pages/sound_explorer_page.dart';

import 'services/collection_service.dart';
import 'services/detection_history_service.dart';
import 'services/mqtt_service.dart';
import 'services/notification_service.dart';
import 'services/online_species_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ParkLifeBootstrap());
}

class ParkLifeBootstrap extends StatelessWidget {
  const ParkLifeBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<OnlineSpeciesService>(
          create: (_) => OnlineSpeciesService(),
        ),
        Provider<NotificationService>(
          create: (_) => NotificationService()..init(),
        ),
        ChangeNotifierProvider<CollectionService>(
          create: (_) => CollectionService(),
        ),
        ChangeNotifierProvider<DetectionHistoryService>(
          create: (_) => DetectionHistoryService(),
        ),

        // 注意：这里不要传 notificationService，不要改 MqttService。
        ChangeNotifierProvider<MqttService>(
          create: (context) => MqttService(
            onlineSpeciesService: context.read<OnlineSpeciesService>(),
            collectionService: context.read<CollectionService>(),
          )..connect(),
        ),
      ],
      child: const DetectionEventBridge(
        child: ParkLifeMonitorApp(),
      ),
    );
  }
}

class DetectionEventBridge extends StatefulWidget {
  final Widget child;

  const DetectionEventBridge({
    super.key,
    required this.child,
  });

  @override
  State<DetectionEventBridge> createState() => _DetectionEventBridgeState();
}

class _DetectionEventBridgeState extends State<DetectionEventBridge> {
  MqttService? _mqttService;
  int _lastHandledAnimationTrigger = 0;

  final Map<String, DateTime> _lastNotificationAt = <String, DateTime>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final service = context.read<MqttService>();

    if (_mqttService == service) return;

    _mqttService?.removeListener(_handleMqttChanged);
    _mqttService = service;

    // App 启动时如果 MqttService 已经有旧 latestEvent，不通知、不重复保存。
    _lastHandledAnimationTrigger = service.animationTrigger;

    _mqttService?.addListener(_handleMqttChanged);
  }

  void _handleMqttChanged() {
    final mqtt = _mqttService;
    if (mqtt == null) return;

    final DetectionEvent? event = mqtt.latestEvent;
    if (event == null) return;

    if (mqtt.animationTrigger <= _lastHandledAnimationTrigger) {
      return;
    }

    _lastHandledAnimationTrigger = mqtt.animationTrigger;

    final history = context.read<DetectionHistoryService>();
    final collection = context.read<CollectionService>();

    history.addEvent(event);

    // 不影响 MQTT，只是保证 Discover 解锁状态也保存。
    collection.unlockFromEvent(event);

    _maybeShowNotification(event);
  }

  void _maybeShowNotification(DetectionEvent event) {
    final String key = event.speciesKey;
    final DateTime now = DateTime.now();
    final DateTime? last = _lastNotificationAt[key];

    // 同一种物种 45 秒内只通知一次，避免刷屏。
    if (last != null && now.difference(last).inSeconds < 45) {
      return;
    }

    _lastNotificationAt[key] = now;

    context.read<NotificationService>().showDetectionNotification(event);
  }

  @override
  void dispose() {
    _mqttService?.removeListener(_handleMqttChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class ParkLifeMonitorApp extends StatelessWidget {
  const ParkLifeMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Park Life Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7EF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4E8F5B),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Color(0xFFF4F7EF),
        ),
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  final List<Widget> _pages = const [
    LiveHabitatPage(),
    NatureDiaryPage(),
    SoundExplorerPage(),
    CollectionPage(),
    DeviceStatusPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() {
            _index = value;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.park_rounded),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_rounded),
            label: 'Diary',
          ),
          NavigationDestination(
            icon: Icon(Icons.graphic_eq_rounded),
            label: 'Atlas',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_rounded),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_input_antenna_rounded),
            label: 'Device',
          ),
        ],
      ),
    );
  }
}