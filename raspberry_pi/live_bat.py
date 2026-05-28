import os
import json
import time
import shutil
import subprocess
from datetime import datetime
from mqtt_config import (
    MQTT_BROKER,
    MQTT_PORT,
    MQTT_USERNAME,
    MQTT_PASSWORD,
    BAT_DETECTION_TOPIC,
    BAT_STATUS_TOPIC,
)

import paho.mqtt.client as mqtt


# =========================
# Basic settings
# =========================

DEVICE_ID = "wuyitong-pi"

# Your UltraMic from arecord -l:
# card 2: r4 [UltraMic 192K 16 bit r4], device 0
ALSA_DEVICE = "hw:2,0"

SAMPLE_RATE = 192000
CHANNELS = 1
RECORD_SECONDS = 10

BASE_DIR = "/home/wuyitong0325"

BAT_AUDIO_DIR = os.path.join(BASE_DIR, "bat_audio")
BAT_OUTPUT_DIR = os.path.join(BASE_DIR, "bat_outputs")

MQTT_TOPIC = BAT_DETECTION_TOPIC
MQTT_STATUS_TOPIC = BAT_STATUS_TOPIC

# BatDetect2 detection threshold.
# For testing, 0.1 is easier to see results.
# For real deployment, you can change it to 0.3 or 0.5.
DETECTION_THRESHOLD = 0.1

# Sleep time between recordings
LOOP_SLEEP_SECONDS = 2


# =========================
# Prepare folders
# =========================

os.makedirs(BAT_AUDIO_DIR, exist_ok=True)
os.makedirs(BAT_OUTPUT_DIR, exist_ok=True)


# =========================
# MQTT setup
# =========================

client = mqtt.Client()
client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
client.connect(MQTT_BROKER, MQTT_PORT, 60)


def publish_status(status, extra=None):
    payload = {
        "device_id": DEVICE_ID,
        "type": "bat",
        "status": status,
        "timestamp": datetime.now().isoformat()
    }

    if extra:
        payload.update(extra)

    print(payload)
    client.publish(MQTT_STATUS_TOPIC, json.dumps(payload))


def publish_detection(detection):
    print(detection)
    client.publish(MQTT_TOPIC, json.dumps(detection))


# =========================
# Record ultrasonic audio
# =========================

def record_ultrasonic_audio():
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    wav_path = os.path.join(BAT_AUDIO_DIR, f"bat_{timestamp}.wav")

    print(f"Recording ultrasonic audio: {wav_path}")

    cmd = [
        "arecord",
        "-D", ALSA_DEVICE,
        "-f", "S16_LE",
        "-r", str(SAMPLE_RATE),
        "-c", str(CHANNELS),
        "-d", str(RECORD_SECONDS),
        wav_path
    ]

    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    if result.returncode != 0:
        raise RuntimeError(
            "arecord failed:\n"
            + result.stdout
            + "\n"
            + result.stderr
        )

    return wav_path


# =========================
# Run BatDetect2
# =========================

def run_batdetect2(wav_path):
    """
    Current installed BatDetect2 command format:

        batdetect2 detect AUDIO_DIR ANN_DIR DETECTION_THRESHOLD

    So we create a temporary input folder, copy the latest wav into it,
    and let BatDetect2 save annotation files into a matching output folder.
    """

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")

    input_dir = os.path.join(BAT_OUTPUT_DIR, f"input_{run_id}")
    output_dir = os.path.join(BAT_OUTPUT_DIR, f"output_{run_id}")

    os.makedirs(input_dir, exist_ok=True)
    os.makedirs(output_dir, exist_ok=True)

    copied_wav = os.path.join(input_dir, os.path.basename(wav_path))
    shutil.copy2(wav_path, copied_wav)

    print("Running BatDetect2...")

    cmd = [
        "/home/wuyitong0325/batdetect-env/bin/batdetect2",
        "detect",
        input_dir,
        output_dir,
        str(DETECTION_THRESHOLD)
    ]

    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    if result.stdout:
        print(result.stdout)

    if result.stderr:
        print(result.stderr)

    if result.returncode != 0:
        raise RuntimeError(
            "BatDetect2 failed:\n"
            + result.stdout
            + "\n"
            + result.stderr
        )

    return output_dir


# =========================
# Parse BatDetect2 output
# =========================

def find_json_files(folder):
    json_files = []

    for root, _, files in os.walk(folder):
        for name in files:
            if name.lower().endswith(".json"):
                json_files.append(os.path.join(root, name))

    return json_files


def extract_detection_list(data):
    """
    BatDetect2 output structure may vary by version.
    This function tries several common keys.
    """

    if isinstance(data, list):
        return data

    if not isinstance(data, dict):
        return []

    possible_keys = [
        "predictions",
        "detections",
        "annotation",
        "annotations",
        "results",
        "events"
    ]

    for key in possible_keys:
        value = data.get(key)
        if isinstance(value, list):
            return value

    return []


def get_first_existing(item, keys, default=None):
    for key in keys:
        if key in item:
            return item[key]
    return default


def parse_batdetect2_outputs(output_dir, wav_path):
    json_files = find_json_files(output_dir)

    if not json_files:
        print("No BatDetect2 JSON output found.")
        return []

    all_detections = []

    for json_path in json_files:
        print(f"Reading result: {json_path}")

        try:
            with open(json_path, "r") as f:
                data = json.load(f)
        except Exception as e:
            print(f"Could not read JSON file {json_path}: {e}")
            continue

        items = extract_detection_list(data)

        for item in items:
            if not isinstance(item, dict):
                continue

            confidence = get_first_existing(
                item,
                ["confidence", "score", "probability", "class_prob", "det_prob"],
                0
            )

            try:
                confidence = float(confidence)
            except Exception:
                confidence = 0.0

            if confidence < DETECTION_THRESHOLD:
                continue

            species = get_first_existing(
                item,
                ["species", "class", "class_name", "label", "event"],
                "unknown_bat"
            )

            start_time = get_first_existing(
                item,
                ["start_time", "start", "time_start", "start_s"],
                None
            )

            end_time = get_first_existing(
                item,
                ["end_time", "end", "time_end", "end_s"],
                None
            )

            detection = {
                "device_id": DEVICE_ID,
                "type": "bat",
                "species": species,
                "confidence": confidence,
                "start_time": start_time,
                "end_time": end_time,
                "audio_file": wav_path,
                "result_file": json_path,
                "timestamp": datetime.now().isoformat(),
                "source": "batdetect2"
            }

            all_detections.append(detection)

    return all_detections


# =========================
# Main loop
# =========================

def main():
    print("Starting live bat detection with UltraMic + BatDetect2...")

    publish_status("started", {
        "sample_rate": SAMPLE_RATE,
        "record_seconds": RECORD_SECONDS,
        "alsa_device": ALSA_DEVICE,
        "detection_threshold": DETECTION_THRESHOLD
    })

    while True:
        try:
            wav_path = record_ultrasonic_audio()

            publish_status("recorded", {
                "audio_file": wav_path
            })

            output_dir = run_batdetect2(wav_path)

            detections = parse_batdetect2_outputs(output_dir, wav_path)

            if detections:
                print("Detected bats:")
                for detection in detections:
                    publish_detection(detection)
            else:
                print("No bats detected.")
                publish_status("no_bats_detected", {
                    "audio_file": wav_path
                })

        except KeyboardInterrupt:
            print("Stopping bat detection...")
            publish_status("stopped")
            break

        except Exception as e:
            print(f"Error: {e}")
            publish_status("error", {
                "message": str(e)
            })
            time.sleep(5)

        time.sleep(LOOP_SLEEP_SECONDS)


if __name__ == "__main__":
    main()
