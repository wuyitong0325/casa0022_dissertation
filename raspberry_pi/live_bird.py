import csv
import json
import socket
import time
from time import perf_counter
from datetime import datetime
from pathlib import Path

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

AUDIO_DEVICE_ID = "hw:2,0"

SAMPLE_RATE = 192000
CHANNELS = 1

# Changed from 15s to 3s for experiment
RECORD_SECONDS = 3

WAV_FILE = "/home/wuyitong0325/live.wav"

# Duty cycle log file on Raspberry Pi
TIMING_LOG_FILE = Path("/home/wuyitong0325/bird_duty_cycle_log.csv")

# Real-time copy to your Windows PC
# Keep receive_bird_log.py running on the PC before starting this script.
PC_IP = "10.129.115.101"
PC_PORT = 5005
SEND_TO_PC = True
PC_SEND_TIMEOUT_SECONDS = 1.0

# Delay between cycles
LOOP_SLEEP_SECONDS = 2

BIRDNET_MIN_CONFIDENCE = 0.30
PUBLISH_CONFIDENCE = 0.50
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


def now_iso():
    return datetime.now().isoformat()


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
            f"confidence={confidence:.2f}",
            flush=True,
        )
        return False

    if looks_like_bad_or_non_bird(common_name, scientific_name):
        print(
            f"Ignored non-bird/noise candidate: {common_name} / {scientific_name} "
            f"confidence={confidence:.2f}",
            flush=True,
        )
        return False

    return True


# =========================
# Duty cycle logging
# =========================

def ensure_timing_log_header():
    if TIMING_LOG_FILE.exists():
        return

    with open(TIMING_LOG_FILE, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([
            "timestamp",
            "record_seconds_setting",
            "sample_rate",
            "recording_time_s",
            "analysis_time_s",
            "sleep_time_s",
            "other_overhead_s",
            "total_cycle_time_s",
            "blind_time_s",
            "duty_cycle_percent",
            "result_status",
            "candidate_count",
            "valid_count",
            "weak_count",
            "rejected_count",
            "best_common_name",
            "best_scientific_name",
            "best_confidence",
        ])


def send_timing_row_to_pc(row):
    """
    Send one CSV row to the Windows receiver.

    This is intentionally non-critical: if the PC is not reachable,
    the Raspberry Pi still continues detecting birds and still saves
    the row locally to TIMING_LOG_FILE.
    """
    if not SEND_TO_PC:
        return

    try:
        line = ",".join(str(item) for item in row) + "\n"

        with socket.create_connection(
            (PC_IP, PC_PORT),
            timeout=PC_SEND_TIMEOUT_SECONDS,
        ) as sock:
            sock.sendall(line.encode("utf-8"))

        print(f"Sent timing row to PC {PC_IP}:{PC_PORT}", flush=True)

    except Exception as e:
        print(f"Could not send timing row to PC: {e}", flush=True)


def log_duty_cycle(
    cycle_start,
    recording_time,
    analysis_time,
    result_status,
    candidate_count=0,
    valid_count=0,
    weak_count=0,
    rejected_count=0,
    best_candidate=None,
):
    sleep_start = perf_counter()
    time.sleep(LOOP_SLEEP_SECONDS)
    sleep_end = perf_counter()

    sleep_time = sleep_end - sleep_start
    total_cycle_time = sleep_end - cycle_start

    blind_time = total_cycle_time - recording_time
    other_overhead = total_cycle_time - recording_time - analysis_time - sleep_time
    duty_cycle = recording_time / total_cycle_time if total_cycle_time > 0 else 0.0

    best_common = ""
    best_scientific = ""
    best_confidence = ""

    if best_candidate:
        best_common = best_candidate.get("common_name", "")
        best_scientific = best_candidate.get("scientific_name", "")
        best_confidence = best_candidate.get("confidence", "")

    print("----------------------------------------", flush=True)
    print(f"Recording time : {recording_time:.1f} s", flush=True)
    print(f"Analysis time  : {analysis_time:.1f} s", flush=True)
    print(f"Sleep time     : {sleep_time:.1f} s", flush=True)
    print(f"Other overhead : {other_overhead:.1f} s", flush=True)
    print(f"Total cycle    : {total_cycle_time:.1f} s", flush=True)
    print(f"Blind time     : {blind_time:.1f} s", flush=True)
    print(f"Duty cycle     : {duty_cycle * 100:.1f} %", flush=True)
    print("----------------------------------------", flush=True)

    ensure_timing_log_header()

    row = [
        now_iso(),
        RECORD_SECONDS,
        SAMPLE_RATE,
        round(recording_time, 1),
        round(analysis_time, 1),
        round(sleep_time, 1),
        round(other_overhead, 1),
        round(total_cycle_time, 1),
        round(blind_time, 1),
        round(duty_cycle * 100, 1),
        result_status,
        candidate_count,
        valid_count,
        weak_count,
        rejected_count,
        best_common,
        best_scientific,
        best_confidence,
    ]

    with open(TIMING_LOG_FILE, "a", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(row)

    send_timing_row_to_pc(row)

    return {
        "recording_time_s": round(recording_time, 1),
        "analysis_time_s": round(analysis_time, 1),
        "sleep_time_s": round(sleep_time, 1),
        "other_overhead_s": round(other_overhead, 1),
        "total_cycle_time_s": round(total_cycle_time, 1),
        "blind_time_s": round(blind_time, 1),
        "duty_cycle_percent": round(duty_cycle * 100, 1),
    }


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
        "timestamp": now_iso(),
    }

    if extra:
        payload.update(extra)

    print("STATUS:", payload, flush=True)

    client.publish(
        BIRD_STATUS_TOPIC,
        json.dumps(payload),
        retain=True,
    )


def publish_detection(payload):
    print("DETECTION:", payload, flush=True)

    client.publish(
        BIRD_DETECTION_TOPIC,
        json.dumps(payload),
        retain=False,
    )


# =========================
# BirdNET setup
# =========================

print("Labels loaded.", flush=True)
print("load model True", flush=True)

analyzer = Analyzer()

print("Model loaded.", flush=True)
print("Labels loaded.", flush=True)
print("load_species_list_model", flush=True)
print("Meta model loaded.", flush=True)
print("Starting live bird detection with 3s recording window...", flush=True)
print(f"Duty cycle log: {TIMING_LOG_FILE}", flush=True)
print(f"Real-time PC log target: {PC_IP}:{PC_PORT}", flush=True)


# =========================
# Main loop
# =========================

while True:
    try:
        cycle_start = perf_counter()

        print("Recording...", flush=True)

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

        record_start = perf_counter()

        audio = sd.rec(
            int(RECORD_SECONDS * SAMPLE_RATE),
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype="int16",
            device=AUDIO_DEVICE_ID,
        )

        sd.wait()

        record_end = perf_counter()
        recording_time = record_end - record_start

        write(WAV_FILE, SAMPLE_RATE, audio)

        print(f"Saved wav: {WAV_FILE}", flush=True)
        print("Analyzing...", flush=True)

        analysis_start = perf_counter()

        recording = Recording(
            analyzer,
            WAV_FILE,
            min_conf=BIRDNET_MIN_CONFIDENCE,
        )

        recording.analyze()

        detections = recording.detections

        analysis_end = perf_counter()
        analysis_time = analysis_end - analysis_start

        candidate_count = len(detections)

        if candidate_count == 0:
            print("No birds detected.", flush=True)

            publish_status(
                "no_birds_detected",
                {
                    "audio_file": WAV_FILE,
                    "birdnet_min_confidence": BIRDNET_MIN_CONFIDENCE,
                    "publish_confidence": PUBLISH_CONFIDENCE,
                    "record_seconds": RECORD_SECONDS,
                    "recording_time_s": round(recording_time, 1),
                    "analysis_time_s": round(analysis_time, 1),
                },
            )

            log_duty_cycle(
                cycle_start=cycle_start,
                recording_time=recording_time,
                analysis_time=analysis_time,
                result_status="no_birds_detected",
                candidate_count=0,
            )

            continue

        print("\nDetected candidates:\n", flush=True)

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
                f"confidence={confidence:.2f} "
                f"time={start_time:.1f}-{end_time:.1f}s",
                flush=True,
            )

            if confidence > best_confidence:
                best_confidence = confidence
                best_candidate = {
                    "common_name": common_name,
                    "scientific_name": scientific_name,
                    "confidence": round(confidence, 3),
                }

            if looks_like_bad_or_non_bird(common_name, scientific_name):
                rejected_count += 1
                print(
                    f"Rejected non-bird/noise candidate: "
                    f"{common_name} / {scientific_name}",
                    flush=True,
                )
                continue

            if confidence < PUBLISH_CONFIDENCE:
                weak_count += 1
                print(
                    f"Weak candidate, not publishing to detections/bird: "
                    f"{common_name} / {scientific_name} confidence={confidence:.2f}",
                    flush=True,
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
                "record_seconds": RECORD_SECONDS,
                "recording_time_s": round(recording_time, 1),
                "analysis_time_s": round(analysis_time, 1),
                "timestamp": now_iso(),
            }

            if should_publish_detection(common_name, scientific_name, confidence):
                publish_detection(payload)
                valid_count += 1
            else:
                rejected_count += 1
                print("Detection was not published to MQTT detections/bird.", flush=True)

        if valid_count > 0:
            result_status = "bird_detected"

            publish_status(
                "bird_detected",
                {
                    "count": valid_count,
                    "weak_count": weak_count,
                    "rejected_count": rejected_count,
                    "candidate_count": candidate_count,
                    "best_candidate": best_candidate,
                    "record_seconds": RECORD_SECONDS,
                    "recording_time_s": round(recording_time, 1),
                    "analysis_time_s": round(analysis_time, 1),
                    "birdnet_min_confidence": BIRDNET_MIN_CONFIDENCE,
                    "publish_confidence": PUBLISH_CONFIDENCE,
                },
            )

        elif weak_count > 0:
            result_status = "weak_signal"

            extra = {
                "audio_file": WAV_FILE,
                "reason": "weak_bird_candidates_below_publish_threshold",
                "weak_count": weak_count,
                "rejected_count": rejected_count,
                "candidate_count": candidate_count,
                "record_seconds": RECORD_SECONDS,
                "recording_time_s": round(recording_time, 1),
                "analysis_time_s": round(analysis_time, 1),
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
            result_status = "no_valid_birds_detected"

            publish_status(
                "no_valid_birds_detected",
                {
                    "audio_file": WAV_FILE,
                    "reason": "detections_filtered_as_noise_or_non_bird",
                    "rejected_count": rejected_count,
                    "candidate_count": candidate_count,
                    "record_seconds": RECORD_SECONDS,
                    "recording_time_s": round(recording_time, 1),
                    "analysis_time_s": round(analysis_time, 1),
                    "birdnet_min_confidence": BIRDNET_MIN_CONFIDENCE,
                    "publish_confidence": PUBLISH_CONFIDENCE,
                },
            )

        log_duty_cycle(
            cycle_start=cycle_start,
            recording_time=recording_time,
            analysis_time=analysis_time,
            result_status=result_status,
            candidate_count=candidate_count,
            valid_count=valid_count,
            weak_count=weak_count,
            rejected_count=rejected_count,
            best_candidate=best_candidate,
        )

    except KeyboardInterrupt:
        print("Stopping live bird detection...", flush=True)
        publish_status("stopped")
        break

    except Exception as e:
        print(f"Bird detection error: {e}", flush=True)

        publish_status(
            "error",
            {
                "message": str(e),
            },
        )

        time.sleep(5)


client.loop_stop()
client.disconnect()