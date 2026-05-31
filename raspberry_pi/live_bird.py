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
# Based on your previous Raspberry Pi setup, "hw:2,0" is your microphone.
# If recording fails, try changing this to None.
AUDIO_DEVICE_ID = "hw:2,0"

SAMPLE_RATE = 192000
CHANNELS = 1
RECORD_SECONDS = 15
WAV_FILE = "/home/wuyitong0325/live.wav"

# BirdNET candidate threshold.
# This allows us to see weak candidates in logs/status, but not publish them as real detections.
BIRDNET_MIN_CONFIDENCE = 0.30

# Only publish detections above this threshold to MQTT detections/bird.
# This prevents random low-confidence species from entering the app Diary.
PUBLISH_CONFIDENCE = 0.50

# Anything between BIRDNET_MIN_CONFIDENCE and PUBLISH_CONFIDENCE is treated as weak signal.
WEAK_CONFIDENCE = 0.30


# =========================
# Filters
# =========================

BAD_LABELS = [
    "engine",
    "noise",
    "speech",
    "human",
    "vehicle",
    "car",
    "traffic",
    "wind",
    "music",
    "radio",
    "conversation",
]

NON_BIRD_COMMON_WORDS = [
    "wolf",
    "dog",
    "fox",
    "cat",
    "bear",
    "cow",
    "goat",
    "sheep",
    "pig",
    "horse",
    "rat",
    "mouse",
    "squirrel",
    "frog",
    "toad",
    "bat",
    "insect",
    "cricket",
]

NON_BIRD_SCIENTIFIC_PREFIXES = [
    "canis ",
    "vulpes ",
    "felis ",
    "lynx ",
    "ursus ",
    "bos ",
    "ovis ",
    "capra ",
    "sus ",
    "equus ",
    "rattus ",
    "mus ",
    "sciurus ",
    "rana ",
    "bufo ",
    "hyla ",
    "pipistrellus ",
    "myotis ",
    "plecotus ",
    "eptesicus ",
    "nyctalus ",
    "rhinolophus ",
]


def looks_like_bad_or_non_bird(common_name, scientific_name):
    common = (common_name or "").lower().strip()
    scientific = (scientific_name or "").lower().strip()
    joined = f"{common} {scientific}"

    for word in BAD_LABELS:
        if word in joined:
            return True

    for word in NON_BIRD_COMMON_WORDS:
        if word in common:
            return True

    for prefix in NON_BIRD_SCIENTIFIC_PREFIXES:
        if scientific.startswith(prefix):
            return True

    return False


def should_publish_detection(common_name, scientific_name, confidence):
    if confidence < PUBLISH_CONFIDENCE:
        print(
            f"Ignored weak bird candidate: {common_name} / {scientific_name} "
            f"confidence={confidence:.2f}"
        )
        return False

    if looks_like_bad_or_non_bird(common_name, scientific_name):
        print(
            f"Ignored non-bird/noise candidate: {common_name} / {scientific_name} "
            f"confidence={confidence:.2f}"
        )
        return False

    return True


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

    print("STATUS:", payload)

    client.publish(
        BIRD_STATUS_TOPIC,
        json.dumps(payload),
        retain=True,
    )


def publish_detection(payload):
    print("DETECTION:", payload)

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

        publish_status(
            "listening",
            {
                "audio_file": WAV_FILE,
                "record_seconds": RECORD_SECONDS,
                "sample_rate": SAMPLE_RATE,
                "birdnet_min_confidence": BIRDNET_MIN_CONFIDENCE,
                "publish_confidence": PUBLISH_CONFIDENCE,
            },
        )

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
            min_conf=BIRDNET_MIN_CONFIDENCE,
        )

        recording.analyze()

        detections = recording.detections

        if len(detections) == 0:
            print("No birds detected.")

            publish_status(
                "no_birds_detected",
                {
                    "audio_file": WAV_FILE,
                    "birdnet_min_confidence": BIRDNET_MIN_CONFIDENCE,
                    "publish_confidence": PUBLISH_CONFIDENCE,
                },
            )

            time.sleep(2)
            continue

        print("\nDetected candidates:\n")

        valid_count = 0
        weak_count = 0
        rejected_count = 0

        best_candidate = None
        best_confidence = 0.0

        for d in detections:
            common_name = str(d.get("common_name", "Unknown"))
            scientific_name = str(d.get("scientific_name", "Unknown"))

            try:
                confidence = float(d.get("confidence", 0.0))
            except Exception:
                confidence = 0.0

            start_time = float(d.get("start_time", 0.0))
            end_time = float(d.get("end_time", 0.0))

            print(
                f"Candidate: {common_name} / {scientific_name} "
                f"confidence={confidence:.2f}"
            )

            if confidence > best_confidence:
                best_confidence = confidence
                best_candidate = {
                    "common_name": common_name,
                    "scientific_name": scientific_name,
                    "confidence": confidence,
                }

            if looks_like_bad_or_non_bird(common_name, scientific_name):
                rejected_count += 1
                print(
                    f"Rejected non-bird/noise candidate: "
                    f"{common_name} / {scientific_name}"
                )
                continue

            if confidence < PUBLISH_CONFIDENCE:
                weak_count += 1
                print(
                    f"Weak candidate, not publishing to detections/bird: "
                    f"{common_name} / {scientific_name} confidence={confidence:.2f}"
                )
                continue

            payload = {
                "device_id": DEVICE_ID,
                "type": "bird",
                "status": "bird_detected",
                "common_name": common_name,
                "scientific_name": scientific_name,
                "confidence": confidence,
                "start_time": start_time,
                "end_time": end_time,
                "audio_file": WAV_FILE,
                "timestamp": datetime.now().isoformat(),
            }

            if should_publish_detection(common_name, scientific_name, confidence):
                publish_detection(payload)
                valid_count += 1
            else:
                rejected_count += 1
                print("Detection was not published to MQTT detections/bird.")

        if valid_count > 0:
            publish_status(
                "bird_detected",
                {
                    "count": valid_count,
                    "weak_count": weak_count,
                    "rejected_count": rejected_count,
                    "birdnet_min_confidence": BIRDNET_MIN_CONFIDENCE,
                    "publish_confidence": PUBLISH_CONFIDENCE,
                },
            )

        elif weak_count > 0:
            extra = {
                "audio_file": WAV_FILE,
                "reason": "weak_bird_candidates_below_publish_threshold",
                "weak_count": weak_count,
                "rejected_count": rejected_count,
                "birdnet_min_confidence": BIRDNET_MIN_CONFIDENCE,
                "publish_confidence": PUBLISH_CONFIDENCE,
            }

            if best_candidate:
                extra.update(
                    {
                        "candidate_common_name": best_candidate["common_name"],
                        "candidate_scientific_name": best_candidate["scientific_name"],
                        "candidate_confidence": best_candidate["confidence"],
                    }
                )

            publish_status("weak_signal", extra)

        else:
            publish_status(
                "no_valid_birds_detected",
                {
                    "audio_file": WAV_FILE,
                    "reason": "detections_filtered_as_noise_or_non_bird",
                    "rejected_count": rejected_count,
                    "birdnet_min_confidence": BIRDNET_MIN_CONFIDENCE,
                    "publish_confidence": PUBLISH_CONFIDENCE,
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
