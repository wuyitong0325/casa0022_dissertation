MQTT_BROKER = "mqtt.cetools.org"
MQTT_PORT = 1884

MQTT_USERNAME = "student"
MQTT_PASSWORD = "CHANGE ME" # not the real password, please change it to the actual password provided by your instructor

BASE_TOPIC = "student/wuyitong0325/park_life_monitor"

MODE_TOPIC = f"{BASE_TOPIC}/status/mode"
BIRD_STATUS_TOPIC = f"{BASE_TOPIC}/status/bird"
BAT_STATUS_TOPIC = f"{BASE_TOPIC}/status/bat"

BIRD_DETECTION_TOPIC = f"{BASE_TOPIC}/detections/bird"
BAT_DETECTION_TOPIC = f"{BASE_TOPIC}/detections/bat"
