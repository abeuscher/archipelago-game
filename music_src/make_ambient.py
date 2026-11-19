"""Placeholder ambient sounds for the island view, synthesised from noise.

Writes to assets/audio/:
  ambient_ocean.wav   24 s seamless loop: a low wash with waves rolling in
  ambient_island.wav  24 s seamless loop: a breeze in the leaves, a few small birds
  gull_1..4.wav       single gull calls, played now and then at random

Everything that runs past the end of a loop wraps round to the start (noise is
shaped in the frequency domain, which is circular), so the loops have no seam.
Replace any of these with a real recording of the same name whenever you like.

    python music_src/make_ambient.py
"""
import os
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "audio")
SR = 44100
LOOP = 24.0


def save(path, x):
    x = np.atleast_2d(x)
    pcm = (np.clip(x, -1, 1).T * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(x.shape[0])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def shaped_noise(n, rng, shape):
    """White noise filtered by shape(freqs) -> gain, circularly."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    x = np.fft.irfft(spec * shape(f), n)
    return x / np.sqrt((x ** 2).mean())


def lowpass(fc, order=2):
    return lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order))


def bandpass(lo, hi):
    return lambda f: (1 / np.sqrt(1 + (lo / np.maximum(f, 1)) ** 4)) / np.sqrt(1 + (f / hi) ** 4)


def circ_env(n, events, shape_fn):
    """Sum of envelopes centred at event times, wrapped round the loop."""
    t = np.arange(n) / SR
    out = np.zeros(n)
    for at, amp in events:
        d = (t - at) % LOOP          # time since the event, wrapping
        out += amp * shape_fn(d)
    return out


def slow_lfo(n, rng, cycles=(1, 2, 3, 5)):
    """A gentle wobble made of whole cycles per loop, so it loops too."""
    t = np.arange(n) / SR
    x = sum(rng.uniform(0.3, 1) * np.sin(2 * np.pi * c * t / LOOP + rng.uniform(0, 6.28)) for c in cycles)
    return x / np.abs(x).max()


def ocean(rng):
    n = int(SR * LOOP)
    # Wave times: one every 5-7 s, a bit different each side.
    times = []
    at = 0.8
    while at < LOOP - 1:
        times.append((at, rng.uniform(0.7, 1.0)))
        at += rng.uniform(5.0, 7.0)

    def swell(d):   # the water rising: up over 2 s, down over 3.5 s
        return np.where(d < 2.0, (d / 2.0) ** 2, np.exp(-(d - 2.0) / 1.6))

    def wash(d):    # the break and fizz just after the peak
        d2 = d - 1.8
        return np.where(d2 < 0, 0, np.minimum(1, d2 / 0.25) * np.exp(-np.maximum(d2, 0) / 1.1))

    chans = []
    for c in range(2):
        jitter = [(t + rng.uniform(-0.25, 0.25), a) for t, a in times]
        bed = shaped_noise(n, rng, lowpass(350)) * (0.35 + 0.1 * slow_lfo(n, rng))
        rumble = shaped_noise(n, rng, lowpass(180, 3)) * circ_env(n, jitter, swell) * 0.7
        fizz = shaped_noise(n, rng, bandpass(900, 5000)) * circ_env(n, jitter, wash) * 0.32
        chans.append(bed + rumble + fizz)
    shared = shaped_noise(n, rng, lowpass(250)) * 0.25
    x = np.array([chans[0] + shared, chans[1] + shared])
    return x / np.abs(x).max() * 0.7


def chirp(rng):
    """One small bird's note: a quick pitch flick."""
    d = rng.uniform(0.04, 0.09)
    m = int(SR * d)
    t = np.arange(m) / SR
    f0, f1 = rng.uniform(3200, 4200), rng.uniform(4500, 6200)
    if rng.random() < 0.5:
        f0, f1 = f1, f0
    f = f0 + (f1 - f0) * (t / d) ** 0.7
    env = np.sin(np.pi * t / d) ** 2
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env


def island(rng):
    n = int(SR * LOOP)
    x = np.zeros((2, n))
    for c in range(2):
        breeze = shaped_noise(n, rng, bandpass(1500, 6000))
        gust = 0.5 + 0.5 * slow_lfo(n, rng, (1, 2, 4, 7))
        x[c] = breeze * (0.04 + 0.11 * gust ** 2)
    # A few birds: little phrases of 2-5 notes every 3-6 s, each from one side.
    at = rng.uniform(0.5, 2)
    while at < LOOP - 0.5:
        pan = rng.uniform(-0.8, 0.8)
        notes = rng.integers(2, 6)
        t = at
        for _ in range(notes):
            s = chirp(rng) * rng.uniform(0.15, 0.3)
            i0 = int(t * SR)
            idx = (np.arange(len(s)) + i0) % n
            x[0, idx] += s * np.sqrt((1 - pan) / 2)
            x[1, idx] += s * np.sqrt((1 + pan) / 2)
            t += len(s) / SR + rng.uniform(0.04, 0.12)
        at += rng.uniform(3.0, 6.0)
    return x / np.abs(x).max() * 0.6


def gull(rng, calls):
    """A herring-gull-ish 'kyow', repeated 'calls' times, quicker each time."""
    out = []
    for k in range(calls):
        d = rng.uniform(0.32, 0.42) * (0.75 ** k)
        m = int(SR * d)
        t = np.arange(m) / SR
        u = t / d
        # Pitch: a quick rise then a long fall, the 'ky-ow'.
        f = np.where(u < 0.2, 950 + 650 * (u / 0.2), 1600 - 700 * (np.maximum(u - 0.2, 0) / 0.8) ** 1.3) * rng.uniform(0.92, 1.08)
        f *= 1 + 0.015 * np.sin(2 * np.pi * 28 * t)
        ph = 2 * np.pi * np.cumsum(f) / SR
        tone = sum(w * np.sin(h * ph) for h, w in zip(range(1, 9), (1, .9, .7, .55, .35, .22, .12, .06)))
        tone = np.tanh(1.8 * tone / 3)                     # a bit of rasp
        rough = 1 + 0.25 * np.sin(2 * np.pi * 55 * t)
        env = np.minimum(1, u / 0.06) * np.minimum(1, (1 - u) / 0.25)
        out.append(tone * rough * env)
        out.append(np.zeros(int(SR * rng.uniform(0.06, 0.12))))
    x = np.concatenate(out + [np.zeros(int(SR * 0.3))])
    # Distance: dull the top end and add a little echo off the water.
    spec = np.fft.rfft(x)
    spec *= lowpass(3500)(np.fft.rfftfreq(len(x), 1 / SR))
    x = np.fft.irfft(spec, len(x))
    echo = np.zeros_like(x)
    lag = int(SR * 0.09)
    echo[lag:] = x[:-lag] * 0.25
    x = x + echo
    return x / np.abs(x).max() * 0.7


if __name__ == "__main__":
    rng = np.random.default_rng(2026)
    save(os.path.join(OUT, "ambient_ocean.wav"), ocean(rng))
    save(os.path.join(OUT, "ambient_island.wav"), island(rng))
    for i, calls in enumerate((1, 2, 3, 2), 1):
        save(os.path.join(OUT, f"gull_{i}.wav"), gull(rng, calls))
    print("wrote ambient_ocean, ambient_island, gull_1..4 to", os.path.normpath(OUT))
