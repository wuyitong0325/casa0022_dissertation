import json
import time
from datetime import datetime

import sounddevice as sd
from scipy.io.wavfile import write
import paho.mqtt.client as mqtt

from birdnetlib import Recording
from birdnetlib.analyzer import Analyzer

from mqtt_config import (
    MQTT_BROKER,
    MQTT_PORT,
    MQTT_USERNAME,
    MQTT_PASSWORD,
    BIRD_DETECTION_TOPIC,
    BIRD_STATUS_TOPIC,
)


# =========================
# Basic settings
# =========================

DEVICE_ID = "wuyitong-pi"

# Your sounddevice input device.
# Based on your previous Raspberry Pi output, device 1 was "default".
# If recording fails, try changing this to None o
AUDIO_DEVICE_ID = "hw:2,0"

SAMPLE_RATE = 192000
CHANNELS = 1
RECORD_SECONDS = 15
WAV_FILE = "live.wav"

MIN_CONFIDENCE = 0.15

# Filter obvious non-wildlife labels.
# Your model produced "Engine", so we skip these before publishing to MQTT.
BAD_LABELS = [
    "engine",
    "noise",
    "speech",
    "human",
    "vehicle",
    "car",
    "traffic",
    "wind",
]


# =========================
# MQTT setup
# =========================

client = mqtt.Client()
client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
client.connect(MQTT_BROKER, MQTT_PORT, 60)
client.loop_start()


def publish_status(status, extra=None):
    payload = {
        "device_id": DEVICE_ID,
        "type": "bird",
        "status": status,
        "timestamp": datetime.now().isoformat(),
    }

    if extra:
        payload.update(extra)

    print(payload)

    client.publish(
        BIRD_STATUS_TOPIC,
        json.dumps(payload),
        retain=True,
    )


def publish_detection(payload):
    print(payload)

    client.publish(
        BIRD_DETECTION_TOPIC,
        json.dumps(payload),
        retain=False,
    )


# =========================
# BirdNET setup
# =========================

print("Labels loaded.")
print("load model True")

analyzer = Analyzer()

print("Model loaded.")
print("Labels loaded.")
print("load_species_list_model")
print("Meta model loaded.")
print("Starting live bird detection...")


# =========================
# Main loop
# =========================

while True:
    try:
        print("Recording...")

        audio = sd.rec(
            int(RECORD_SECONDS * SAMPLE_RATE),
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype="int16",
            device=AUDIO_DEVICE_ID,
        )

        sd.wait()

        write(WAV_FILE, SAMPLE_RATE, audio)

        print("Analyzing...")

        recording = Recording(
            analyzer,
            WAV_FILE,
            min_conf=MIN_CONFIDENCE,
        )

        recording.analyze()

        detections = recording.detections

        valid_count = 0

        if len(detections) == 0:
            print("No birds detected.")

            publish_status(
                "no_birds_detected",
                {
                    "audio_file": WAV_FILE,
                    "min_confidence": MIN_CONFIDENCE,
                },
            )

        else:
            print("\nDetected species:\n")

            for d in detections:
                common_name = str(d.get("common_name", "Unknown"))
                scientific_name = str(d.get("scientific_name", "Unknown"))
                confidence = float(d.get("confidence", 0.0))

                lower_name = common_name.lower()

                if any(bad in lower_name for bad in BAD_LABELS):
                    print(f"Skipping non-wildlife label: {common_name}")
                    continue

                payload = {
                    "device_id": DEVICE_ID,
                    "type": "bird",
                    "common_name": common_name,
                    "scientific_name": scientific_name,
                    "confidence": confidence,
                    "start_time": float(d.get("start_time", 0.0)),
                    "end_time": float(d.get("end_time", 0.0)),
                    "timestamp": datetime.now().isoformat(),
                }

                publish_detection(payload)
                valid_count += 1

            if valid_count == 0:
                publish_status(
                    "no_valid_birds_detected",
                    {
                        "audio_file": WAV_FILE,
                        "reason": "detections_filtered_as_noise_or_non_wildlife",
                        "min_confidence": MIN_CONFIDENCE,
                    },
                )
            else:
                publish_status(
                    "bird_detected",
                    {
                        "count": valid_count,
                        "min_confidence": MIN_CONFIDENCE,
                    },
                )

        time.sleep(2)

    except KeyboardInterrupt:
        print("Stopping live bird detection...")
        publish_status("stopped")
        break

    except Exception as e:
        print(f"Bird detection error: {e}")

        publish_status(
            "error",
            {
                "message": str(e),
            },
        )

        time.sleep(5)


client.loop_stop()
client.disconnect()
