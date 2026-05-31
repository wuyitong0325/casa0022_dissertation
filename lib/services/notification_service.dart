import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/detection_event.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _wildlifeChannel =
      AndroidNotificationChannel(
    'wildlife_detection_channel',
    'Wildlife detections',
    description: 'Notifications for bird and bat detections from MQTT.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(initSettings);

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(_wildlifeChannel);

    await _requestNotificationPermission();

    _ready = true;
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;

    if (status.isDenied || status.isRestricted || status.isLimited) {
      await Permission.notification.request();
    }
  }

  Future<void> showDetectionNotification(DetectionEvent event) async {
    await init();

    final isBat = event.isBat;
    final emoji = isBat ? '🦇' : '🐦';

    final title = isBat
        ? '$emoji Bat detected!'
        : '$emoji Bird detected!';

    final confidence = (event.confidence * 100).toStringAsFixed(0);

    final body = '${event.commonName} · confidence $confidence%';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _wildlifeChannel.id,
        _wildlifeChannel.name,
        channelDescription: _wildlifeChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
        ticker: title,
        visibility: NotificationVisibility.public,
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(
          '$body\nScientific name: ${event.scientificName}',
          contentTitle: title,
          summaryText: 'Park Life Monitor',
        ),
      ),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: event.speciesKey,
    );
  }

  Future<void> showStatusNotification({
    required String title,
    required String body,
  }) async {
    await init();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _wildlifeChannel.id,
        _wildlifeChannel.name,
        channelDescription: _wildlifeChannel.description,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.status,
      ),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }
}