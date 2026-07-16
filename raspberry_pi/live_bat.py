import argparse
import csv
import json
import os
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

DEVICE_ID = "wuyitong-pi"

AUDIO_DIR = Path("/home/wuyitong0325/bat_audio")
BAT_OUTPUT_DIR = Path("/home/wuyitong0325/bat_outputs")
AUDIO_DIR.mkdir(parents=True, exist_ok=True)
BAT_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

BATDETECT2_BIN = "/home/wuyitong0325/batdetect-env/bin/batdetect2"

SAMPLE_RATE = 192000
CHANNELS = 1
RECORD_SECONDS = 4
ALSA_DEVICE = "hw:2,0"

# Low threshold for BatDetect2 candidate generation.
DETECTION_THRESHOLD = 0.20

# Higher threshold for publishing a detection to the app.
PUBLISH_CONFIDENCE = 0.40
WEAK_CONFIDENCE = 0.20

# Extra filters to reduce false positives from laptop noise, speech, and electrical noise.
MIN_CALL_COUNT = 2
MIN_HIGH_FREQ = 30000
MIN_CALL_DURATION = 0.005
MAX_CALL_DURATION = 0.30

BATDETECT_TIMEOUT_SECONDS = 180
LOOP_SLEEP_SECONDS = 0

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
    client.publish(BAT_STATUS_TOPIC, json.dumps(payload), retain=True)


def publish_detection(payload):
    print("DETECTION:", payload, flush=True)
    client.publish(BAT_DETECTION_TOPIC, json.dumps(payload), retain=False)


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


def record_ultrasonic_audio(record_seconds=RECORD_SECONDS):
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    wav_path = AUDIO_DIR / f"bat_{timestamp}.wav"

    print("=" * 80, flush=True)
    print(f"RECORDING {record_seconds}s ultrasonic audio...", flush=True)
    print(f"File: {wav_path}", flush=True)

    publish_status(
        "recording",
        {
            "sample_rate": SAMPLE_RATE,
            "record_seconds": record_seconds,
            "alsa_device": ALSA_DEVICE,
        },
    )

    frames = int(record_seconds * SAMPLE_RATE)

    audio = sd.rec(
        frames,
        samplerate=SAMPLE_RATE,
        channels=CHANNELS,
        dtype="int16",
        device=ALSA_DEVICE if ALSA_DEVICE else None,
    )

    sd.wait()
    write(str(wav_path), SAMPLE_RATE, audio)

    print(f"RECORDED: {wav_path}", flush=True)

    publish_status(
        "recorded",
        {
            "audio_file": str(wav_path),
            "sample_rate": SAMPLE_RATE,
            "record_seconds": record_seconds,
        },
    )

    return wav_path



def cleanup_run_files(wav_path=None, input_dir=None, output_dir=None, delete_audio=True):
    """Remove temporary BatDetect2 files after each processing cycle."""
    targets = [
        ("input directory", Path(input_dir) if input_dir else None, True),
        ("output directory", Path(output_dir) if output_dir else None, True),
        (
            "recorded audio",
            Path(wav_path) if wav_path and delete_audio else None,
            False,
        ),
    ]

    for label, path, is_directory in targets:
        if path is None:
            continue

        try:
            if is_directory:
                if path.exists():
                    shutil.rmtree(path)
                    print(f"CLEANED {label}: {path}", flush=True)
            else:
                if path.exists():
                    path.unlink()
                    print(f"CLEANED {label}: {path}", flush=True)
        except Exception as e:
            # Cleanup failure should not stop the live detector.
            print(f"WARNING: could not clean {label} {path}: {e}", flush=True)

def run_batdetect2(wav_path, threshold=DETECTION_THRESHOLD):
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

    print("ANALYSING with BatDetect2...", flush=True)
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
        return input_dir, output_dir, "", "Python subprocess timeout", 124

    stdout = result.stdout or ""
    stderr = result.stderr or ""

    print("BatDetect2 return code:", result.returncode, flush=True)

    if stdout.strip():
        print("BatDetect2 stdout:", flush=True)
        print(stdout, flush=True)

    if stderr.strip():
        print("BatDetect2 stderr:", flush=True)
        print(stderr, flush=True)

    return input_dir, output_dir, stdout, stderr, result.returncode


def find_detection_dicts(obj):
    detections = []

    if isinstance(obj, dict):
        if (
            "det_prob" in obj
            or "start_time" in obj
            or "end_time" in obj
            or "event" in obj
            or "class" in obj
            or "species_name" in obj
        ):
            detections.append(obj)

        for value in obj.values():
            detections.extend(find_detection_dicts(value))

    elif isinstance(obj, list):
        for item in obj:
            detections.extend(find_detection_dicts(item))

    return detections


def parse_json_file(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return find_detection_dicts(data)
    except Exception as e:
        print(f"Could not parse JSON file {path}: {e}", flush=True)
        return []


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
                    or "end_time" in normalised
                    or "event" in normalised
                    or "class" in normalised
                    or "species_name" in normalised
                ):
                    detections.append(normalised)

    except Exception as e:
        print(f"Could not parse CSV file {path}: {e}", flush=True)

    return detections


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
        raw.get(
            "det_prob",
            raw.get(
                "confidence",
                raw.get(
                    "score",
                    raw.get("class_prob", 0.0),
                ),
            ),
        ),
        0.0,
    )

    class_probability = safe_float(raw.get("class_prob", 0.0), 0.0)
    start_time = safe_float(raw.get("start_time", raw.get("start", 0.0)), 0.0)
    end_time = safe_float(raw.get("end_time", raw.get("end", 0.0)), 0.0)
    low_freq = safe_int(raw.get("low_freq", raw.get("low_freq_hz", 0)), 0)
    high_freq = safe_int(raw.get("high_freq", raw.get("high_freq_hz", 0)), 0)

    return {
        "device_id": DEVICE_ID,
        "type": "bat",
        "status": "bat_detected",
        "common_name": common_name,
        "scientific_name": species,
        "confidence": confidence,
        "class_probability": class_probability,
        "event": str(raw.get("event", "Echolocation")),
        "start_time": start_time,
        "end_time": end_time,
        "low_freq": low_freq,
        "high_freq": high_freq,
        "audio_file": str(wav_path),
        "timestamp": now_iso(),
        "source": "batdetect2",
    }


def parse_batdetect2_outputs(output_dir, wav_path):
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

    detections = []

    for raw in raw_detections:
        detection = normalise_detection(raw, wav_path)
        if detection:
            detections.append(detection)

    return detections


def is_possible_real_call(detection):
    confidence = safe_float(detection.get("confidence", 0.0), 0.0)
    start_time = safe_float(detection.get("start_time", 0.0), 0.0)
    end_time = safe_float(detection.get("end_time", 0.0), 0.0)
    high_freq = safe_int(detection.get("high_freq", 0), 0)

    duration = end_time - start_time

    if confidence < WEAK_CONFIDENCE:
        return False

    if end_time <= start_time:
        return False

    if duration < MIN_CALL_DURATION or duration > MAX_CALL_DURATION:
        return False

    if high_freq < MIN_HIGH_FREQ:
        return False

    return True


def choose_best_detection(detections):
    if not detections:
        return None

    return max(
        detections,
        key=lambda d: safe_float(d.get("confidence", 0.0), 0.0),
    )


def process_wav(
    wav_path,
    threshold=DETECTION_THRESHOLD,
    publish=True,
    cleanup_audio=False,
):
    """
    Process one WAV file.

    cleanup_audio=True is used by live mode so that the recorded WAV and all
    BatDetect2 input/output folders are removed after every cycle, including
    successful detections, no detections, errors, and timeouts.

    cleanup_audio=False is used for --test-wav so the user's test file is kept.
    """
    wav_path = Path(wav_path)

    print("=" * 80, flush=True)
    print(f"PROCESSING: {wav_path}", flush=True)
    process_start = time.time()

    input_dir = None
    output_dir = None

    try:
        input_dir, output_dir, stdout, stderr, return_code = run_batdetect2(
            wav_path,
            threshold,
        )

        if return_code != 0:
            print(f"BatDetect2 failed: return_code={return_code}", flush=True)

            publish_status(
                "batdetect_error",
                {
                    "audio_file": str(wav_path),
                    "return_code": return_code,
                    "output_dir": str(output_dir),
                    "stderr": stderr[-500:],
                },
            )

            return None

        detections = parse_batdetect2_outputs(output_dir, wav_path)

        process_seconds = time.time() - process_start
        print(f"PROCESSING TIME: {process_seconds:.2f}s", flush=True)
        print(f"Parsed detection count: {len(detections)}", flush=True)

        possible_calls = []

        for d in detections:
            confidence = safe_float(d.get("confidence", 0.0), 0.0)
            start_time = safe_float(d.get("start_time", 0.0), 0.0)
            end_time = safe_float(d.get("end_time", 0.0), 0.0)
            duration = end_time - start_time
            high_freq = safe_int(d.get("high_freq", 0), 0)

            print(
                f"Candidate: {d.get('common_name')} / {d.get('scientific_name')} "
                f"conf={confidence:.2f} "
                f"time={start_time:.3f}-{end_time:.3f}s "
                f"duration={duration:.3f}s "
                f"high_freq={high_freq}",
                flush=True,
            )

            if is_possible_real_call(d):
                possible_calls.append(d)
            else:
                print("Rejected candidate after bat-call filters.", flush=True)

        print(f"Possible real call count: {len(possible_calls)}", flush=True)

        if not possible_calls:
            publish_status(
                "no_bats_detected",
                {
                    "audio_file": str(wav_path),
                    "candidate_count": len(detections),
                    "reason": "no_valid_bat_calls_after_filtering",
                    "detection_threshold": threshold,
                    "publish_confidence": PUBLISH_CONFIDENCE,
                    "weak_confidence": WEAK_CONFIDENCE,
                    "min_high_freq": MIN_HIGH_FREQ,
                    "output_dir": str(output_dir),
                },
            )

            print("NO VALID BAT CALL. No detection published.", flush=True)
            return None

        best = choose_best_detection(possible_calls)
        best_conf = safe_float(best.get("confidence", 0.0), 0.0)

        best["call_count"] = len(possible_calls)
        best["output_dir"] = str(output_dir)
        best["detection_threshold"] = threshold

        if best_conf < PUBLISH_CONFIDENCE or len(possible_calls) < MIN_CALL_COUNT:
            publish_status(
                "weak_signal",
                {
                    "audio_file": str(wav_path),
                    "candidate_count": len(detections),
                    "valid_call_count": len(possible_calls),
                    "best_common_name": best.get("common_name", "Bat"),
                    "best_scientific_name": best.get("scientific_name", "Bat"),
                    "best_confidence": best_conf,
                    "reason": "bat_like_signal_but_not_reliable_enough",
                    "detection_threshold": threshold,
                    "publish_confidence": PUBLISH_CONFIDENCE,
                    "min_call_count": MIN_CALL_COUNT,
                    "output_dir": str(output_dir),
                },
            )

            print("WEAK BAT-LIKE SIGNAL. Status only, no detection published.", flush=True)
            return None

        if publish:
            publish_detection(best)

            publish_status(
                "bat_detected",
                {
                    "audio_file": str(wav_path),
                    "count": len(possible_calls),
                    "best_common_name": best.get("common_name", "Bat"),
                    "best_scientific_name": best.get("scientific_name", "Bat"),
                    "best_confidence": best_conf,
                    "best_class_probability": best.get("class_probability", 0.0),
                    "low_freq": best.get("low_freq", 0),
                    "high_freq": best.get("high_freq", 0),
                    "detection_threshold": threshold,
                    "publish_confidence": PUBLISH_CONFIDENCE,
                },
            )

        return best

    finally:
        cleanup_run_files(
            wav_path=wav_path,
            input_dir=input_dir,
            output_dir=output_dir,
            delete_audio=cleanup_audio,
        )


def run_live_mode(record_seconds=RECORD_SECONDS, threshold=DETECTION_THRESHOLD):
    print("Starting live bat detection...", flush=True)
    print("Pipeline: RECORD -> STOP -> ANALYSE -> PUBLISH -> NEXT", flush=True)
    print(f"record_seconds={record_seconds}, threshold={threshold}", flush=True)

    publish_status(
        "started",
        {
            "sample_rate": SAMPLE_RATE,
            "record_seconds": record_seconds,
            "alsa_device": ALSA_DEVICE,
            "detection_threshold": threshold,
            "pipeline": "record_stop_analyse_publish",
        },
    )

    while True:
        try:
            loop_start = time.time()
            wav_path = record_ultrasonic_audio(record_seconds=record_seconds)
            process_wav(
                wav_path,
                threshold=threshold,
                publish=True,
                cleanup_audio=True,
            )
            loop_seconds = time.time() - loop_start
            print(f"FULL LOOP TIME: {loop_seconds:.2f}s", flush=True)

            if LOOP_SLEEP_SECONDS > 0:
                time.sleep(LOOP_SLEEP_SECONDS)

        except KeyboardInterrupt:
            print("Stopping live bat detection...", flush=True)
            publish_status("stopped")
            break

        except Exception as e:
            print("ERROR:", e, flush=True)
            publish_status("error", {"message": str(e)})
            time.sleep(1)


def run_test_wav_mode(test_wav, threshold=DETECTION_THRESHOLD):
    publish_status(
        "testing_wav",
        {
            "audio_file": str(test_wav),
            "detection_threshold": threshold,
        },
    )

    best = process_wav(
        test_wav,
        threshold=threshold,
        publish=True,
        cleanup_audio=False,
    )

    if best:
        print("BEST DETECTION:", best, flush=True)
    else:
        print("No reliable bat detection published.", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Park Life Monitor bat detection script")
    parser.add_argument("--test-wav", type=str, default=None)
    parser.add_argument("--record-seconds", type=int, default=RECORD_SECONDS)
    parser.add_argument("--threshold", type=float, default=DETECTION_THRESHOLD)

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