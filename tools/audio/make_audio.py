#!/usr/bin/env python3
"""Synthesises every sound in assets/audio/ from scratch (numpy only, deterministic seeds),
then encodes to Ogg Vorbis with ffmpeg. Output is original work released under CC0 1.0.

    python3 tools/audio/make_audio.py
"""
import os, subprocess, wave, tempfile
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
rng = np.random.default_rng(7)


def t_of(sec):
    return np.arange(int(sec * SR)) / SR


def env(n, a=0.005, r=0.2, curve=4.0):
    """attack/exp-release envelope over n samples"""
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(a, 1e-4)) * np.exp(-curve * np.maximum(0, t - a) / max(r, 1e-4))
    return e


def lowpass(x, cutoff):
    # simple one-pole, run twice for 12 dB/oct
    a = np.exp(-2 * np.pi * cutoff / SR)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i in range(len(x)):
            acc = (1 - a) * x[i] + a * acc
            y[i] = acc
        x = y
    return x


def lowpass_fast(x, cutoff):
    # FFT brickwall-ish with smooth roll-off (for long noise beds)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1.0 / (1.0 + (f / cutoff) ** 4)
    return np.fft.irfft(X, len(x))


def bandpass_fast(x, lo, hi):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= (1.0 / (1.0 + (f / hi) ** 4)) * (1.0 / (1.0 + (lo / np.maximum(f, 1)) ** 4))
    return np.fft.irfft(X, len(x))


def pluck(freq, dur, bright=0.5, decay=6.0):
    t = t_of(dur)
    s = np.zeros_like(t)
    for k, amp in enumerate([1.0, 0.45 * bright, 0.25 * bright, 0.12 * bright], start=1):
        s += amp * np.sin(2 * np.pi * freq * k * t) * np.exp(-decay * k * 0.6 * t)
    return s * env(len(t), 0.003, dur, 1.0)


def marimba(freq, dur=0.9):
    t = t_of(dur)
    s = np.sin(2 * np.pi * freq * t) * np.exp(-5.0 * t)
    s += 0.35 * np.sin(2 * np.pi * freq * 4.0 * t) * np.exp(-14.0 * t)
    s += 0.12 * np.sin(2 * np.pi * freq * 9.2 * t) * np.exp(-30.0 * t)
    return s * np.minimum(1, t / 0.002)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def noise(n):
    return rng.standard_normal(n)


def normalize(x, peak=0.8):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def fade_loop(x, fade=0.5):
    """make a seamless loop by cross-fading the tail into the head"""
    n = int(fade * SR)
    head, tail = x[:n].copy(), x[-n:].copy()
    w = np.linspace(0, 1, n)
    if x.ndim == 2:
        w = w[:, None]
    x = x[:-n].copy()
    x[:n] = head * w + tail * (1 - w)
    return x


def write(name, x, stereo=False):
    x = np.clip(x, -1, 1)
    data = (x * 32767).astype(np.int16)
    ch = 1
    if stereo:
        ch = 2
        data = data.reshape(-1)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", out], check=True)
    os.unlink(tmp)
    print("wrote", out)


def stereo(l, r):
    return np.stack([l, r], axis=1)


def main():
    os.makedirs(OUT, exist_ok=True)
    # --- UI
    write("ui_click", normalize(mix(pluck(880, 0.08, 0.3, 30), 0.3 * pluck(1320, 0.06, 0.2, 40)), 0.45))
    write("ui_open", normalize(np.concatenate([pluck(660, 0.07, 0.3, 25), pluck(990, 0.14, 0.3, 18)]), 0.4))
    write("ui_close", normalize(np.concatenate([pluck(990, 0.07, 0.3, 25), pluck(660, 0.14, 0.3, 18)]), 0.35))
    write("ui_error", normalize(mix(pluck(196, 0.12, 0.8, 18), pluck(185, 0.16, 0.8, 14)), 0.5))
    # --- placing things
    n = int(0.25 * SR)
    thunk = lowpass_fast(noise(n), 900) * env(n, 0.002, 0.08, 1.0) + 0.6 * np.sin(2 * np.pi * 110 * t_of(0.25)) * env(n, 0.002, 0.12, 1.0)
    write("build", normalize(thunk, 0.7))
    n = int(0.3 * SR)
    chop = bandpass_fast(noise(n), 600, 3500) * env(n, 0.001, 0.05, 1.0)
    chop2 = np.concatenate([np.zeros(int(0.12 * SR)), chop[: n - int(0.12 * SR)] * 0.6])
    write("chop", normalize(chop + chop2, 0.6))
    n = int(0.35 * SR)
    rustle = bandpass_fast(noise(n), 1500, 7000) * env(n, 0.03, 0.15, 1.0) * 0.5
    write("plant", normalize(mix(rustle, 0.6 * pluck(523.25, 0.35, 0.6, 9)), 0.55))
    n = int(0.4 * SR)
    dig = bandpass_fast(noise(n), 200, 1800) * (env(n, 0.002, 0.06, 1.0) + 0.6 * np.roll(env(n, 0.002, 0.06, 1.0), int(0.17 * SR)))
    write("dig", normalize(dig, 0.6))
    n = int(0.6 * SR)
    splash = bandpass_fast(noise(n), 800, 6000) * env(n, 0.005, 0.25, 1.0)
    write("water", normalize(splash + 0.3 * np.sin(2 * np.pi * (300 + 500 * t_of(0.6)) * t_of(0.6)) * env(n, 0.002, 0.1, 1.0), 0.5))
    # --- notifications
    chime = np.zeros(int(1.2 * SR))
    for k, f in enumerate([659.25, 987.77]):
        s = marimba(f, 1.0)
        o = int(k * 0.09 * SR)
        chime[o:o + len(s)] += s
    write("notify", normalize(chime, 0.4))
    warn = np.zeros(int(1.0 * SR))
    for k, f in enumerate([392.0, 311.13]):
        s = marimba(f, 0.8)
        o = int(k * 0.14 * SR)
        warn[o:o + len(s)] += s
    write("warn", normalize(warn, 0.45))
    win = np.zeros(int(2.4 * SR))
    for k, f in enumerate([523.25, 659.25, 783.99, 1046.5, 1318.5]):
        s = marimba(f, 1.4)
        o = int(k * 0.11 * SR)
        win[o:o + len(s)] += s * (0.8 if k < 4 else 1.0)
    write("win", normalize(win, 0.6))
    lose = np.zeros(int(2.0 * SR))
    for k, f in enumerate([392.0, 349.23, 311.13, 261.63]):
        s = marimba(f, 1.2)
        o = int(k * 0.18 * SR)
        lose[o:o + len(s)] += s
    write("lose", normalize(lose, 0.5))
    star = marimba(1567.98, 0.7) + 0.5 * marimba(2093.0, 0.7)
    write("star", normalize(star, 0.45))
    # --- ambience loops (stereo, seamless)
    dur = 24.0
    n = int(dur * SR)
    tt = t_of(dur)
    waves = []
    for ch in range(2):
        base = lowpass_fast(noise(n), 500)
        swell = 0.55 + 0.45 * np.sin(2 * np.pi * tt / 6.0 + ch * 0.9) ** 2
        hiss = bandpass_fast(noise(n), 1500, 5000) * 0.25 * (0.4 + 0.6 * np.sin(2 * np.pi * tt / 6.0 + ch * 0.9 + 0.6) ** 4)
        waves.append(normalize(base * swell + hiss, 0.35))
    write("amb_sea", fade_loop(stereo(*waves), 1.0), stereo=True)
    rain = []
    for ch in range(2):
        r = bandpass_fast(noise(n), 700, 9000) * 0.6 + lowpass_fast(noise(n), 300) * 0.4
        drops = np.zeros(n)
        for _ in range(900):
            p = rng.integers(0, n - 2000)
            drops[p:p + 1500] += bandpass_fast(noise(1500), 2500, 9000) * env(1500, 0.0005, 0.01, 1.0) * rng.uniform(0.1, 0.5)
        rain.append(normalize(r + drops, 0.4))
    write("amb_rain", fade_loop(stereo(*rain), 1.0), stereo=True)
    # --- music: gentle pentatonic marimba over a soft pad, 32 bars-ish loop
    bpm = 84
    beat = 60.0 / bpm
    bars = 16
    dur = bars * 4 * beat
    n = int(dur * SR) + SR * 2
    mus = np.zeros((n, 2))
    scale = [261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25]
    chords = [[130.81, 196.0, 261.63, 329.63], [110.0, 164.81, 220.0, 261.63], [87.31, 130.81, 174.61, 220.0], [98.0, 146.83, 196.0, 246.94]]
    tt_bar = t_of(4 * beat + 1.0)
    for b in range(bars):
        ch = chords[(b // 2) % 4]
        pad = np.zeros_like(tt_bar)
        for f in ch:
            pad += np.sin(2 * np.pi * f * tt_bar + np.sin(2 * np.pi * 0.3 * tt_bar) * 0.3)
            pad += 0.3 * np.sin(2 * np.pi * f * 2.003 * tt_bar)
        pad *= np.minimum(1, tt_bar / 0.8) * np.minimum(1, np.maximum(0, (4 * beat + 1.0 - tt_bar)) / 1.0) * 0.06
        o = int(b * 4 * beat * SR)
        mus[o:o + len(pad), 0] += pad
        mus[o:o + len(pad), 1] += pad
        mrng = np.random.default_rng(100 + b % 8)
        for k in range(8):
            if mrng.random() < 0.62:
                f = scale[mrng.integers(0, len(scale))]
                s = marimba(f, 1.2) * 0.22
                p = int((b * 4 + k * 0.5) * beat * SR)
                pan = mrng.uniform(0.25, 0.75)
                mus[p:p + len(s), 0] += s * (1 - pan)
                mus[p:p + len(s), 1] += s * pan
    # simple feedback echo for space
    d = int(beat * 0.75 * SR)
    for i in range(3):
        mus[d * (i + 1):] += mus[:-d * (i + 1)] * (0.25 / (i + 1))
    loop_n = int(dur * SR)
    mus[:SR * 2] += mus[loop_n:loop_n + SR * 2]  # wrap the tail into the head
    mus = mus[:loop_n]
    write("music_island", normalize(mus, 0.55), stereo=True)


if __name__ == "__main__":
    main()
