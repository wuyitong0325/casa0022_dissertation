import socket
import csv
from pathlib import Path
from datetime import datetime

HOST = "0.0.0.0"
PORT = 5005

CSV_FILE = Path("bird_duty_cycle_from_pi.csv")

HEADER = [
    "received_time",
    "pi_timestamp",
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
]

def ensure_csv_header():
    if CSV_FILE.exists():
        return

    with open(CSV_FILE, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(HEADER)

def main():
    ensure_csv_header()

    print("Waiting for Raspberry Pi timing data...")
    print(f"Listening on port {PORT}")
    print(f"Saving to: {CSV_FILE.resolve()}")

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind((HOST, PORT))
    server.listen(1)

    while True:
        conn, addr = server.accept()
        print(f"\nConnected from {addr}")

        with conn:
            buffer = ""

            while True:
                data = conn.recv(4096)

                if not data:
                    print("Connection closed by Raspberry Pi.")
                    break

                buffer += data.decode("utf-8", errors="ignore")

                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()

                    if not line:
                        continue

                    row = line.split(",")

                    received_time = datetime.now().isoformat(timespec="seconds")
                    full_row = [received_time] + row

                    with open(CSV_FILE, "a", newline="", encoding="utf-8") as f:
                        writer = csv.writer(f)
                        writer.writerow(full_row)

                    print("Saved:", full_row)

if __name__ == "__main__":
    main()