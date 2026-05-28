import json
import os
import subprocess
import time as time_module
from datetime import datetime, time

import paho.mqtt.client as mqtt

from mqtt_config import MQTT_BROKER, MQTT_PORT, MQTT_USERNAME, MQTT_PASSWORD, MODE_TOPIC


DEVICE_ID = "wuyitong-pi"

BASE_DIR = "/home/wuyitong0325"

BIRD_SCRIPT = os.path.join(BASE_DIR, "live_bird.py")
BAT_SCRIPT = os.path.join(BASE_DIR, "live_bat.py")

BIRD_PYTHON = "/usr/bin/python3"
BAT_PYTHON = os.path.join(BASE_DIR, "batdetect-env/bin/python")

DAY_START = time(6, 0)
NIGHT_START = time(20, 0)

CHECK_INTERVAL_SECONDS = 30


def get_current_mode():
    now = datetime.now().time()

    if DAY_START <= now < NIGHT_START:
        return "bird"

    return "bat"


def get_script_for_mode(mode):
    if mode == "bird":
        return "live_bird.py"

    return "live_bat.py"


def get_command_for_mode(mode):
    if mode == "bird":
        return [BIRD_PYTHON, "-u", BIRD_SCRIPT]

    return [BAT_PYTHON, "-u", BAT_SCRIPT]


def publish_mode(mode):
    payload = {
        "device_id": DEVICE_ID,
        "mode": mode,
        "script": get_script_for_mode(mode),
        "timestamp": datetime.now().isoformat(),
    }

    print(payload)

    try:
        client = mqtt.Client()
        client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
        client.connect(MQTT_BROKER, MQTT_PORT, 60)
        client.loop_start()

        result = client.publish(
            MODE_TOPIC,
            json.dumps(payload),
            retain=True,
        )

        result.wait_for_publish()

        client.loop_stop()
        client.disconnect()

        print("MQTT mode published.")

    except Exception as e:
        print(f"MQTT mode publish failed: {e}")


print("Starting time-based monitor controller...")
print("06:00-20:00 = Bird Mode")
print("20:00-06:00 = Bat Mode")

current_process = None
current_mode = None

try:
    while True:
        new_mode = get_current_mode()

        if new_mode != current_mode:
            print(f"Switching mode: {current_mode} -> {new_mode}")

            if current_process is not None:
                print("Stopping previous process...")
                current_process.terminate()

                try:
                    current_process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    print("Previous process did not stop, killing it...")
                    current_process.kill()

            publish_mode(new_mode)

            command = get_command_for_mode(new_mode)
            print(f"Starting command: {' '.join(command)}")

            current_process = subprocess.Popen(command)
            current_mode = new_mode

        if current_process is not None and current_process.poll() is not None:
            print("Child process stopped unexpectedly. Restarting...")
            command = get_command_for_mode(current_mode)
            print(f"Restarting command: {' '.join(command)}")
            current_process = subprocess.Popen(command)

        time_module.sleep(CHECK_INTERVAL_SECONDS)

except KeyboardInterrupt:
    print("Stopping monitor controller...")

    if current_process is not None:
        current_process.terminate()

except Exception as e:
    print(f"main_monitor error: {e}")

    if current_process is not None:
        current_process.terminate()
