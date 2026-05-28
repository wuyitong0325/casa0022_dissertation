import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/collection_page.dart';
import 'pages/device_status_page.dart';
import 'pages/live_habitat_page.dart';
import 'pages/nature_diary_page.dart';
import 'pages/sound_explorer_page.dart';
import 'services/collection_service.dart';
import 'services/mqtt_service.dart';
import 'services/online_species_service.dart';

void main() {
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
        ChangeNotifierProvider<CollectionService>(
          create: (_) => CollectionService(),
        ),
        ChangeNotifierProvider<MqttService>(
          create: (context) => MqttService(
            onlineSpeciesService: context.read<OnlineSpeciesService>(),
            collectionService: context.read<CollectionService>(),
          )..connect(),
        ),
      ],
      child: const ParkLifeMonitorApp(),
    );
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
          setState(() => _index = value);
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
            label: 'Sound Lab',
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