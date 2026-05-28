class AppMqttConfig {
  static const String broker = 'mqtt.cetools.org';
  static const int port = 1884;

  static const String username = 'student';


  static const String password = String.fromEnvironment('MQTT_PASSWORD');

  static const String baseTopic = 'student/wuyitong0325/park_life_monitor';

  static const String subscribeTopic = '$baseTopic/#';

  static const String modeTopic = '$baseTopic/status/mode';
  static const String birdStatusTopic = '$baseTopic/status/bird';
  static const String batStatusTopic = '$baseTopic/status/bat';

  static const String birdDetectionTopic = '$baseTopic/detections/bird';
  static const String batDetectionTopic = '$baseTopic/detections/bat';
}