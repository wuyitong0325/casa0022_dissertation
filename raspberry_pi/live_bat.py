import argparse
import csv
import json
import os
import re
import shutil
import subprocess
import time
from datetime import datetime
from pathlib import Path

import paho.mqtt.client as mqtt
import sounddevice as sd
from scipy.io.wavfile import write

from mqtt_config import (
    MQTT_BROKER,
    MQTT_PORT,
    MQTT_USERNAME,
    MQTT_PASSWORD,
    BAT_DETECTION_TOPIC,
    BAT_STATUS_TOPIC,
)

# =========================
# Basic settings
# =========================

DEVICE_ID = "wuyitong-pi"

AUDIO_DIR = Path("/home/wuyitong0325/bat_audio")
BAT_OUTPUT_DIR = Path("/home/wuyitong0325/bat_outputs")

AUDIO_DIR.mkdir(parents=True, exist_ok=True)
BAT_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

BATDETECT2_BIN = "/home/wuyitong0325/batdetect-env/bin/batdetect2"

# UltraMic / ultrasonic bat audio settings
SAMPLE_RATE = 192000
CHANNELS = 1
RECORD_SECONDS = 10

# 根据你的设备情况，原来用的可能是 hw:2,0
# 如果录音失败，可以改成 None 或其他设备号。
ALSA_DEVICE = "hw:2,0"

# batdetect2 的 threshold 不能照搬 bird 的 0.5。
# 之前教授 wav 测试中 0.03 可以检测到 52 calls。
DETECTION_THRESHOLD = 0.03

# batdetect2 最大运行时间，防止卡死。
BATDETECT_TIMEOUT_SECONDS = 180

# 每轮之间休息时间
LOOP_SLEEP_SECONDS = 2


BAT_COMMON_NAMES = {
    "Pipistrellus pipistrellus": "Common Pipistrelle",
    "Pipistrellus pygmaeus": "Soprano Pipistrelle",
    "Pipistrellus nathusii": "Nathusius' Pipistrelle",
    "Nyctalus noctula": "Noctule",
    "Nyctalus leisleri": "Leisler's Bat",
    "Eptesicus serotinus": "Serotine",
    "Myotis daubentonii": "Daubenton's Bat",
    "Myotis nattereri": "Natterer's Bat",
    "Plecotus auritus": "Brown Long-eared Bat",
    "Rhinolophus ferrumequinum": "Greater Horseshoe Bat",
    "Rhinolophus hipposideros": "Lesser Horseshoe Bat",
}


# =========================
# MQTT setup
# =========================

client = mqtt.Client()
client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
client.connect(MQTT_BROKER, MQTT_PORT, 60)
client.loop_start()


def now_iso():
    return datetime.now().isoformat()


def publish_status(status, extra=None):
    payload = {
        "device_id": DEVICE_ID,
        "type": "bat",
        "status": status,
        "timestamp": now_iso(),
    }

    if extra:
        payload.update(extra)

    print("STATUS:", payload, flush=True)

    client.publish(
        BAT_STATUS_TOPIC,
        json.dumps(payload),
        retain=True,
    )


def publish_detection(payload):
    print("DETECTION:", payload, flush=True)

    client.publish(
        BAT_DETECTION_TOPIC,
        json.dumps(payload),
        retain=False,
    )


# =========================
# Audio recording
# =========================

def record_ultrasonic_audio(record_seconds=RECORD_SECONDS):
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    wav_path = AUDIO_DIR / f"bat_{timestamp}.wav"

    print(f"Recording ultrasonic audio: {wav_path}", flush=True)

    publish_status(
        "recording",
        {
            "sample_rate": SAMPLE_RATE,
            "record_seconds": record_seconds,
            "alsa_device": ALSA_DEVICE,
        },
    )

    frames = int(record_seconds * SAMPLE_RATE)

    if ALSA_DEVICE:
        audio = sd.rec(
            frames,
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype="int16",
            device=ALSA_DEVICE,
        )
    else:
        audio = sd.rec(
            frames,
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype="int16",
        )

    sd.wait()

    write(str(wav_path), SAMPLE_RATE, audio)

    print(f"Saved wav: {wav_path}", flush=True)

    publish_status(
        "recorded",
        {
            "audio_file": str(wav_path),
            "sample_rate": SAMPLE_RATE,
            "record_seconds": record_seconds,
        },
    )

    return wav_path


# =========================
# Safe BatDetect2 runner
# =========================

def run_batdetect2(wav_path, threshold=DETECTION_THRESHOLD):
    """
    Run BatDetect2 safely on exactly one wav file.

    It creates a temporary input directory, copies one wav into it,
    and runs:
        timeout 180s nice -n 15 batdetect2 detect input_dir output_dir threshold

    Thread-related environment variables are limited to avoid killing the Pi.
    """

    wav_path = Path(wav_path)

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    input_dir = BAT_OUTPUT_DIR / f"input_{run_id}"
    output_dir = BAT_OUTPUT_DIR / f"output_{run_id}"

    input_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    copied_wav = input_dir / wav_path.name
    shutil.copy2(wav_path, copied_wav)

    cmd = [
        "timeout",
        f"{BATDETECT_TIMEOUT_SECONDS}s",
        "nice",
        "-n",
        "15",
        BATDETECT2_BIN,
        "detect",
        str(input_dir),
        str(output_dir),
        str(threshold),
    ]

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "1"
    env["OPENBLAS_NUM_THREADS"] = "1"
    env["MKL_NUM_THREADS"] = "1"
    env["NUMEXPR_NUM_THREADS"] = "1"
    env["NUMBA_NUM_THREADS"] = "1"
    env["NUMBA_CACHE_DIR"] = "/tmp/numba_cache_batdetect"

    print("Running BatDetect2 safely...", flush=True)
    print("CMD:", " ".join(cmd), flush=True)

    publish_status(
        "analysing",
        {
            "audio_file": str(wav_path),
            "input_dir": str(input_dir),
            "output_dir": str(output_dir),
            "detection_threshold": threshold,
            "timeout_seconds": BATDETECT_TIMEOUT_SECONDS,
        },
    )

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=BATDETECT_TIMEOUT_SECONDS + 20,
            env=env,
        )
    except subprocess.TimeoutExpired:
        publish_status(
            "batdetect_timeout",
            {
                "audio_file": str(wav_path),
                "timeout_seconds": BATDETECT_TIMEOUT_SECONDS,
            },
        )
        return output_dir, "", "Python subprocess timeout", 124

    stdout = result.stdout or ""
    stderr = result.stderr or ""

    print("BatDetect2 return code:", result.returncode, flush=True)

    if stdout.strip():
        print("BatDetect2 stdout:", flush=True)
        print(stdout, flush=True)

    if stderr.strip():
        print("BatDetect2 stderr:", flush=True)
        print(stderr, flush=True)

    if result.returncode == 124:
        publish_status(
            "batdetect_timeout",
            {
                "audio_file": str(wav_path),
                "output_dir": str(output_dir),
                "timeout_seconds": BATDETECT_TIMEOUT_SECONDS,
            },
        )
    elif result.returncode != 0:
        publish_status(
            "batdetect_error",
            {
                "audio_file": str(wav_path),
                "output_dir": str(output_dir),
                "return_code": result.returncode,
                "stderr": stderr[-500:],
            },
        )

    return output_dir, stdout, stderr, result.returncode


# =========================
# BatDetect2 output parsing
# =========================

def safe_float(value, default=0.0):
    try:
        return float(value)
    except Exception:
        return default


def safe_int(value, default=0):
    try:
        return int(float(value))
    except Exception:
        return default


def normalise_detection(raw, wav_path):
    if not isinstance(raw, dict):
        return None

    species = (
        raw.get("class")
        or raw.get("species")
        or raw.get("species_name")
        or raw.get("class_name")
        or raw.get("scientific_name")
        or "Bat"
    )

    species = str(species).strip()
    common_name = BAT_COMMON_NAMES.get(species, species if species else "Bat")

    confidence = safe_float(
        raw.get("det_prob",
                raw.get("confidence",
                        raw.get("score",
                                raw.get("probability_present",
                                        raw.get("class_prob", 0.0))))),
        0.0,
    )

    class_probability = safe_float(raw.get("class_prob", raw.get("probability_present", 0.0)), 0.0)

    start_time = safe_float(raw.get("start_time", raw.get("start", 0.0)), 0.0)
    end_time = safe_float(raw.get("end_time", raw.get("end", 0.0)), 0.0)

    low_freq = safe_int(raw.get("low_freq", raw.get("low_freq_hz", 0)), 0)
    high_freq = safe_int(raw.get("high_freq", raw.get("high_freq_hz", 0)), 0)

    event = str(raw.get("event", "Echolocation"))

    return {
        "device_id": DEVICE_ID,
        "type": "bat",
        "status": "bat_detected",
        "common_name": common_name,
        "scientific_name": species,
        "confidence": confidence,
        "class_probability": class_probability,
        "event": event,
        "start_time": start_time,
        "end_time": end_time,
        "low_freq": low_freq,
        "high_freq": high_freq,
        "audio_file": str(wav_path),
        "timestamp": now_iso(),
        "source": "batdetect2",
    }


def find_detection_dicts(obj):
    """
    Recursively find detection-like dictionaries from BatDetect2 JSON outputs.
    """

    detections = []

    if isinstance(obj, dict):
        if (
            "det_prob" in obj
            or "start_time" in obj
            or "event" in obj
            or "probability_present" in obj
        ):
            detections.append(obj)

        for value in obj.values():
            detections.extend(find_detection_dicts(value))

    elif isinstance(obj, list):
        for item in obj:
            detections.extend(find_detection_dicts(item))

    return detections


def parse_json_file(path):
    detections = []

    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        detections.extend(find_detection_dicts(data))
    except Exception as e:
        print(f"Could not parse JSON file {path}: {e}", flush=True)

    return detections


def parse_csv_file(path):
    detections = []

    try:
        with open(path, "r", encoding="utf-8", newline="") as f:
            reader = csv.DictReader(f)

            for row in reader:
                normalised = {}

                for key, value in row.items():
                    if key is None:
                        continue

                    clean_key = key.strip().lower().replace(" ", "_")
                    normalised[clean_key] = value

                if (
                    "det_prob" in normalised
                    or "start_time" in normalised
                    or "event" in normalised
                    or "class" in normalised
                    or "species_name" in normalised
                ):
                    detections.append(normalised)

    except Exception as e:
        print(f"Could not parse CSV file {path}: {e}", flush=True)

    return detections


def parse_stdout_summary(stdout):
    """
    Parse BatDetect2 stdout summary like:

    species_name                probability_present
    Pipistrellus pipistrellus   0.944
    Pipistrellus nathusii       0.018
    """

    detections = []

    if not stdout:
        return detections

    lines = stdout.splitlines()

    found_header = False

    for line in lines:
        stripped = line.strip()

        if not stripped:
            continue

        if "species_name" in stripped and "probability" in stripped:
            found_header = True
            continue

        if found_header:
            match = re.match(r"^([A-Za-z]+(?:\s+[a-zA-Z]+)+)\s+([0-9]*\.?[0-9]+)$", stripped)

            if match:
                species = match.group(1).strip()
                prob = safe_float(match.group(2), 0.0)

                detections.append(
                    {
                        "class": species,
                        "species_name": species,
                        "probability_present": prob,
                        "event": "Echolocation",
                    }
                )

    return detections


def parse_batdetect2_outputs(output_dir, wav_path, stdout=""):
    raw_detections = []

    output_dir = Path(output_dir)

    if output_dir.exists():
        for path in output_dir.rglob("*"):
            if not path.is_file():
                continue

            suffix = path.suffix.lower()

            if suffix == ".json":
                raw_detections.extend(parse_json_file(path))
            elif suffix == ".csv":
                raw_detections.extend(parse_csv_file(path))

    if not raw_detections:
        raw_detections.extend(parse_stdout_summary(stdout))

    detections = []

    for raw in raw_detections:
        detection = normalise_detection(raw, wav_path)

        if detection:
            detections.append(detection)

    return detections


def choose_best_detection(detections):
    if not detections:
        return None

    return max(
        detections,
        key=lambda d: safe_float(
            d.get("confidence", d.get("class_probability", 0.0)),
            0.0,
        ),
    )


# =========================
# Full processing
# =========================

def process_wav(wav_path, threshold=DETECTION_THRESHOLD, publish=True):
    wav_path = Path(wav_path)

    print("=" * 80, flush=True)
    print(f"Processing bat wav: {wav_path}", flush=True)

    output_dir, stdout, stderr, return_code = run_batdetect2(wav_path, threshold)

    if return_code not in (0,):
        print(f"BatDetect2 did not finish normally. return_code={return_code}", flush=True)
        return None

    detections = parse_batdetect2_outputs(output_dir, wav_path, stdout)

    print(f"Parsed detection count: {len(detections)}", flush=True)

    strong = [
        d for d in detections
        if safe_float(d.get("confidence", 0.0), 0.0) >= threshold
        or safe_float(d.get("class_probability", 0.0), 0.0) >= threshold
    ]

    print(f"Strong detection count: {len(strong)}", flush=True)

    if not strong:
        publish_status(
            "no_bats_detected",
            {
                "audio_file": str(wav_path),
                "detection_threshold": threshold,
                "output_dir": str(output_dir),
            },
        )
        return None

    best = choose_best_detection(strong)

    if best is None:
        publish_status(
            "no_bats_detected",
            {
                "audio_file": str(wav_path),
                "detection_threshold": threshold,
                "output_dir": str(output_dir),
            },
        )
        return None

    best["call_count"] = len(strong)
    best["output_dir"] = str(output_dir)
    best["detection_threshold"] = threshold

    if publish:
        publish_detection(best)

        publish_status(
            "bat_detected",
            {
                "audio_file": str(wav_path),
                "count": len(strong),
                "best_common_name": best.get("common_name", "Bat"),
                "best_scientific_name": best.get("scientific_name", "Bat"),
                "best_confidence": best.get("confidence", 0.0),
                "best_class_probability": best.get("class_probability", 0.0),
                "low_freq": best.get("low_freq", 0),
                "high_freq": best.get("high_freq", 0),
                "detection_threshold": threshold,
            },
        )

    return best


# =========================
# Main modes
# =========================

def run_live_mode(record_seconds=RECORD_SECONDS, threshold=DETECTION_THRESHOLD):
    print("Starting live bat detection with UltraMic + BatDetect2...", flush=True)

    publish_status(
        "started",
        {
            "sample_rate": SAMPLE_RATE,
            "record_seconds": record_seconds,
            "alsa_device": ALSA_DEVICE,
            "detection_threshold": threshold,
            "batdetect2_mode": "safe_single_wav",
        },
    )

    while True:
        try:
            wav_path = record_ultrasonic_audio(record_seconds=record_seconds)
            process_wav(wav_path, threshold=threshold, publish=True)

            time.sleep(LOOP_SLEEP_SECONDS)

        except KeyboardInterrupt:
            print("Stopping live bat detection...", flush=True)
            publish_status("stopped")
            break

        except Exception as e:
            print("ERROR:", e, flush=True)
            publish_status(
                "error",
                {
                    "message": str(e),
                },
            )
            time.sleep(LOOP_SLEEP_SECONDS)


def run_test_wav_mode(test_wav, threshold=DETECTION_THRESHOLD):
    publish_status(
        "testing_wav",
        {
            "audio_file": str(test_wav),
            "detection_threshold": threshold,
        },
    )

    best = process_wav(test_wav, threshold=threshold, publish=True)

    if best:
        print("BEST DETECTION:", best, flush=True)
    else:
        print("No bat detection published.", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Park Life Monitor bat detection script")

    parser.add_argument(
        "--test-wav",
        type=str,
        default=None,
        help="Analyse one existing wav file and publish the result to MQTT.",
    )

    parser.add_argument(
        "--record-seconds",
        type=int,
        default=RECORD_SECONDS,
        help="Recording duration for live mode.",
    )

    parser.add_argument(
        "--threshold",
        type=float,
        default=DETECTION_THRESHOLD,
        help="BatDetect2 detection threshold.",
    )

    args = parser.parse_args()

    if args.test_wav:
        run_test_wav_mode(args.test_wav, threshold=args.threshold)
    else:
        run_live_mode(record_seconds=args.record_seconds, threshold=args.threshold)


if __name__ == "__main__":
    try:
        main()
    finally:
        client.loop_stop()
        client.disconnect()
