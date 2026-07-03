import argparse
from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt
from scipy.io import wavfile
from scipy.signal import spectrogram, resample_poly


def read_wav_mono(path):
    sr, audio = wavfile.read(str(path))
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    audio = audio.astype(np.float32)
    peak = np.max(np.abs(audio)) if audio.size else 1.0
    if peak > 0:
        audio = audio / peak
    return sr, audio


def resample_to(sr, audio, target_sr):
    if sr == target_sr:
        return audio
    from math import gcd
    g = gcd(sr, target_sr)
    up = target_sr // g
    down = sr // g
    return resample_poly(audio, up, down).astype(np.float32)


def make_spec(sr, audio, max_freq):
    nperseg = 1024
    noverlap = 768
    f, t, sxx = spectrogram(
        audio,
        fs=sr,
        window="hann",
        nperseg=nperseg,
        noverlap=noverlap,
        scaling="spectrum",
        mode="magnitude",
    )
    sxx_db = 20 * np.log10(sxx + 1e-8)
    mask = f <= max_freq
    return f[mask], t, sxx_db[mask, :]


def band_energy(sr, audio, low, high):
    # Simple FFT-band energy over the full clip, useful for quick comparison.
    if audio.size == 0:
        return 0.0
    win = np.hanning(len(audio))
    spec = np.abs(np.fft.rfft(audio * win)) ** 2
    freqs = np.fft.rfftfreq(len(audio), d=1.0 / sr)
    mask = (freqs >= low) & (freqs <= high)
    return float(np.sum(spec[mask]) + 1e-12)


def plot_pair(reference_path, recorded_path, output_path, title, max_freq):
    ref_sr, ref_audio = read_wav_mono(reference_path)
    rec_sr, rec_audio = read_wav_mono(recorded_path)

    # Compare both at the same sample rate, limited to useful bird range.
    target_sr = min(ref_sr, rec_sr, 48000)
    ref_audio = resample_to(ref_sr, ref_audio, target_sr)
    rec_audio = resample_to(rec_sr, rec_audio, target_sr)
    ref_sr = rec_sr = target_sr

    ref_f, ref_t, ref_s = make_spec(ref_sr, ref_audio, max_freq)
    rec_f, rec_t, rec_s = make_spec(rec_sr, rec_audio, max_freq)

    ref_low = band_energy(ref_sr, ref_audio, 1000, 3000)
    ref_mid = band_energy(ref_sr, ref_audio, 3000, 8000)
    ref_high = band_energy(ref_sr, ref_audio, 8000, min(12000, ref_sr / 2))

    rec_low = band_energy(rec_sr, rec_audio, 1000, 3000)
    rec_mid = band_energy(rec_sr, rec_audio, 3000, 8000)
    rec_high = band_energy(rec_sr, rec_audio, 8000, min(12000, rec_sr / 2))

    # Ratios are easier to discuss in the report than raw FFT numbers.
    ref_total = ref_low + ref_mid + ref_high
    rec_total = rec_low + rec_mid + rec_high
    ref_ratios = [100 * ref_low / ref_total, 100 * ref_mid / ref_total, 100 * ref_high / ref_total]
    rec_ratios = [100 * rec_low / rec_total, 100 * rec_mid / rec_total, 100 * rec_high / rec_total]

    fig = plt.figure(figsize=(12, 9))

    ax1 = fig.add_subplot(3, 1, 1)
    ax1.pcolormesh(ref_t, ref_f / 1000, ref_s, shading="auto")
    ax1.set_title("Reference / expected bird call spectrum")
    ax1.set_ylabel("Frequency (kHz)")
    ax1.set_ylim(0, max_freq / 1000)

    ax2 = fig.add_subplot(3, 1, 2)
    ax2.pcolormesh(rec_t, rec_f / 1000, rec_s, shading="auto")
    ax2.set_title("Raspberry Pi recorded spectrum")
    ax2.set_ylabel("Frequency (kHz)")
    ax2.set_xlabel("Time (s)")
    ax2.set_ylim(0, max_freq / 1000)

    ax3 = fig.add_subplot(3, 1, 3)
    labels = ["1-3 kHz", "3-8 kHz", "8-12 kHz"]
    x = np.arange(len(labels))
    width = 0.35
    ax3.bar(x - width / 2, ref_ratios, width, label="Reference")
    ax3.bar(x + width / 2, rec_ratios, width, label="Recorded")
    ax3.set_xticks(x)
    ax3.set_xticklabels(labels)
    ax3.set_ylabel("Relative band energy (%)")
    ax3.set_title("Frequency-band energy comparison")
    ax3.legend()

    fig.suptitle(title)
    fig.tight_layout()
    fig.savefig(str(output_path), dpi=200)
    print(f"Saved: {output_path}")
    print("Reference band energy % [1-3, 3-8, 8-12 kHz]:", [round(v, 1) for v in ref_ratios])
    print("Recorded  band energy % [1-3, 3-8, 8-12 kHz]:", [round(v, 1) for v in rec_ratios])


def main():
    parser = argparse.ArgumentParser(description="Compare reference and Raspberry Pi recorded bird-call spectrograms.")
    parser.add_argument("--reference", required=True, help="Reference/expected bird call WAV file.")
    parser.add_argument("--recorded", required=True, help="Raspberry Pi recorded WAV file.")
    parser.add_argument("--out", default="spectrogram_comparison.png", help="Output PNG path.")
    parser.add_argument("--species", default="Bird call", help="Species name for the figure title.")
    parser.add_argument("--max-freq", type=int, default=12000, help="Maximum frequency to display, Hz.")
    args = parser.parse_args()

    plot_pair(
        Path(args.reference),
        Path(args.recorded),
        Path(args.out),
        args.species,
        args.max_freq,
    )


if __name__ == "__main__":
    main()
