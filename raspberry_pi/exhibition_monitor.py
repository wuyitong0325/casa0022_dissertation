import json
import os
import signal
import subprocess
import time as time_module
from datetime import datetime

import paho.mqtt.client as mqtt

from mqtt_config import (
    MQTT_BROKER,
    MQTT_PORT,
    MQTT_USERNAME,
    MQTT_PASSWORD,
    MODE_TOPIC,
)


DEVICE_ID = "wuyitong-pi"

BASE_DIR = "/home/wuyitong0325"

BIRD_SCRIPT = os.path.join(BASE_DIR, "live_bird.py")
BAT_SCRIPT = os.path.join(BASE_DIR, "live_bat.py")

BIRD_PYTHON = "/usr/bin/python3"
BAT_PYTHON = "/usr/bin/python3"

# App 手动控制用的 topic
# App 发 bird / bat / stop 到这个 topic
COMMAND_TOPIC = "student/wuyitong0325/park_life_monitor/command/mode"

CHECK_INTERVAL_SECONDS = 2

current_process = None
current_mode = "none"
mqtt_client = None


def get_script_for_mode(mode):
    if mode == "bird":
        return "live_bird.py"

    if mode == "bat":
        return "live_bat.py"

    return "none"


def get_command_for_mode(mode):
    if mode == "bird":
        return [BIRD_PYTHON, "-u", BIRD_SCRIPT]

    if mode == "bat":
        return [BAT_PYTHON, "-u", BAT_SCRIPT]

    raise ValueError(f"Unknown mode: {mode}")


def normalise_command(payload_text):
    """
    Accept both simple text and JSON commands.

    Valid simple payload:
      bird
      bat
      stop

    Valid JSON payload:
      {"mode": "bird"}
      {"mode": "bat"}
      {"mode": "stop"}
    """
    text = payload_text.strip()

    if not text:
        return None

    lowered = text.lower()

    if lowered in ["bird", "bat", "stop"]:
        return lowered

    try:
        data = json.loads(text)

        if isinstance(data, dict):
            mode = str(data.get("mode", "")).lower().strip()

            if mode in ["bird", "bat", "stop"]:
                return mode

    except Exception:
        pass

    return None


def publish_mode_status(mode, status="running", message=None):
    """
    Publish current exhibition controller mode to the existing MODE_TOPIC.
    App can use this retained message to show current mode/status.
    """
    global mqtt_client

    payload = {
        "device_id": DEVICE_ID,
        "mode": mode,
        "script": get_script_for_mode(mode),
        "status": status,
        "controller": "exhibition_manual",
        "message": message,
        "timestamp": datetime.now().isoformat(),
    }

    print("Publishing mode/status:")
    print(payload)

    try:
        if mqtt_client is None:
            print("MQTT client not ready. Cannot publish status.")
            return

        result = mqtt_client.publish(
            MODE_TOPIC,
            json.dumps(payload),
            retain=True,
        )

        print("MQTT mode/status queued.")

    except Exception as e:
        print(f"MQTT mode/status publish failed: {e}")


def stop_current_process():
    """
    Stop currently running live_bird.py or live_bat.py process.
    This version is stronger for exhibition use: it kills the whole process group
    and then runs pkill as a safety fallback.
    """
    global current_process
    global current_mode

    old_mode = current_mode

    if current_process is not None:
        print(f"Stopping current process: {old_mode}")

        try:
            # Kill the whole child process group first.
            os.killpg(os.getpgid(current_process.pid), signal.SIGTERM)

            try:
                current_process.wait(timeout=8)
                print("Process group terminated cleanly.")
            except subprocess.TimeoutExpired:
                print("Process group did not stop. Killing it...")
                os.killpg(os.getpgid(current_process.pid), signal.SIGKILL)
                current_process.wait(timeout=5)

        except Exception as e:
            print(f"Process group stop failed: {e}")

            try:
                current_process.terminate()
                current_process.wait(timeout=5)
            except Exception:
                try:
                    current_process.kill()
                except Exception:
                    pass

    # Safety fallback: make sure no detector process is left running.
    try:
        subprocess.run(["pkill", "-f", "live_bird.py"], check=False)
        subprocess.run(["pkill", "-f", "live_bat.py"], check=False)
        subprocess.run(["pkill", "-f", "batdetect2"], check=False)
    except Exception as e:
        print(f"Fallback pkill failed: {e}")

    current_process = None
    current_mode = "none"


def switch_mode(new_mode):
    """
    Manual exhibition mode switching.
    This is triggered by App/MQTT command, not by clock time.
    """
    global current_process
    global current_mode

    if new_mode == "stop":
        stop_current_process()
        publish_mode_status(
            "none",
            status="stopped",
            message="Manual stop from exhibition controller.",
        )
        return

    if new_mode not in ["bird", "bat"]:
        print(f"Ignoring invalid mode: {new_mode}")
        publish_mode_status(
            current_mode,
            status="invalid_mode",
            message=f"Invalid mode: {new_mode}",
        )
        return

    if (
        current_mode == new_mode
        and current_process is not None
        and current_process.poll() is None
    ):
        print(f"Already running {new_mode} mode.")
        publish_mode_status(
            new_mode,
            status="already_running",
            message=f"{new_mode} mode is already running.",
        )
        return

    print(f"Manual switch requested: {current_mode} -> {new_mode}")

    stop_current_process()

    command = get_command_for_mode(new_mode)

    print(f"Starting command: {' '.join(command)}")

    try:
        current_process = subprocess.Popen(
            command,
            preexec_fn=os.setsid,
        )

        current_mode = new_mode

        publish_mode_status(
            new_mode,
            status="running",
            message="Manual exhibition mode selected.",
        )

    except Exception as e:
        current_process = None
        current_mode = "none"

        print(f"Failed to start {new_mode} mode: {e}")

        publish_mode_status(
            "none",
            status="start_failed",
            message=f"Failed to start {new_mode}: {e}",
        )


def on_connect(client, userdata, flags, rc):
    print(f"Connected to MQTT broker with result code: {rc}")

    if rc == 0:
        client.subscribe(COMMAND_TOPIC)
        print(f"Subscribed to command topic: {COMMAND_TOPIC}")

        publish_mode_status(
            "none",
            status="ready",
            message="Exhibition monitor ready. Waiting for App command.",
        )
    else:
        print("MQTT connection failed.")


def on_disconnect(client, userdata, rc):
    print(f"Disconnected from MQTT broker. rc={rc}")


def on_message(client, userdata, msg):
    try:
        payload_text = msg.payload.decode("utf-8", errors="replace")
    except Exception:
        payload_text = ""

    print(f"Command received on {msg.topic}: {payload_text}")

    command = normalise_command(payload_text)

    if command is None:
        print("Invalid command. Expected bird, bat, stop, or JSON {'mode':'bird'}.")

        publish_mode_status(
            current_mode,
            status="invalid_command",
            message=f"Invalid command: {payload_text}",
        )

        return

    switch_mode(command)


def restart_child_if_needed():
    """
    If live_bird.py or live_bat.py stops unexpectedly while a mode is active,
    restart it automatically.
    """
    global current_process
    global current_mode

    if current_mode not in ["bird", "bat"]:
        return

    if current_process is None:
        return

    if current_process.poll() is None:
        return

    print(f"{current_mode} child process stopped unexpectedly. Restarting...")

    try:
        command = get_command_for_mode(current_mode)

        print(f"Restarting command: {' '.join(command)}")

        current_process = subprocess.Popen(
            command,
            preexec_fn=os.setsid,
        )

        publish_mode_status(
            current_mode,
            status="restarted",
            message="Child process stopped unexpectedly and was restarted.",
        )

    except Exception as e:
        print(f"Failed to restart child process: {e}")

        publish_mode_status(
            current_mode,
            status="restart_failed",
            message=str(e),
        )


def main():
    global mqtt_client

    print("Starting Park Life Monitor exhibition controller...")
    print("Manual mode only. No time-based bird/bat switching.")
    print(f"MQTT broker: {MQTT_BROKER}:{MQTT_PORT}")
    print(f"Command topic: {COMMAND_TOPIC}")
    print("Send one of: bird / bat / stop")
    print("Or JSON: {'mode':'bird'} / {'mode':'bat'} / {'mode':'stop'}")

    mqtt_client = mqtt.Client()
    mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    mqtt_client.on_connect = on_connect
    mqtt_client.on_disconnect = on_disconnect
    mqtt_client.on_message = on_message

    try:
        mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
        mqtt_client.loop_start()

        while True:
            restart_child_if_needed()
            time_module.sleep(CHECK_INTERVAL_SECONDS)

    except KeyboardInterrupt:
        print("Stopping exhibition controller...")
        stop_current_process()

    except Exception as e:
        print(f"exhibition_monitor error: {e}")
        stop_current_process()

    finally:
        try:
            publish_mode_status(
                "none",
                status="offline",
                message="Exhibition monitor stopped.",
            )
        except Exception:
            pass

        try:
            mqtt_client.loop_stop()
            mqtt_client.disconnect()
        except Exception:
            pass


if __name__ == "__main__":
    main()
