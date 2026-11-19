"""Archipelago's three themes, written out as notes.

Writes music_src/{build,battle,intro}_theme.mid (General MIDI, open them in any
DAW and swap instruments) and a rough preview .wav of each from a tiny
built-in synth. The previews loop seamlessly: the reverb and note tails that
run past the end wrap round to the start.

    python music_src/compose_themes.py
"""
import os
import struct
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SR = 44100
PPQ = 480

# ---------------------------------------------------------------- notation

PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def pitch(name):
    """'C#5' -> 73, 'Bb4' -> 70."""
    pc = PC[name[0]]
    rest = name[1:]
    while rest and rest[0] in "#b":
        pc += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + pc


def phrase(text, start_bar):
    """'r:1 C5:0.5 F5:0.5 | A5:2 ...' -> [(beat, beats, pitch)]; '|' is a bar line check."""
    out = []
    beat = start_bar * 4.0
    for tok in text.split():
        if tok == "|":
            continue
        name, dur = tok.split(":")
        dur = float(dur)
        if name != "r":
            out.append((beat, dur, pitch(name)))
        beat += dur
    return out, beat


CHORDS = {
    "F": [5, 9, 0], "Dm": [2, 5, 9], "Bb": [10, 2, 5], "C": [0, 4, 7], "C7": [0, 4, 7, 10],
    "Gm": [7, 10, 2], "Am": [9, 0, 4], "A": [9, 1, 4], "A7": [9, 1, 4, 7],
}


def chord_spans(bars, start_bar):
    """['F', 'Gm C', ...] -> [(beat, beats, chord)], two chords in a bar get two beats each."""
    out = []
    for i, bar in enumerate(bars):
        names = bar.split()
        each = 4.0 / len(names)
        for j, n in enumerate(names):
            out.append(((start_bar + i) * 4.0 + j * each, each, n))
    return out


def voicing(name, low):
    return sorted(low + ((pc - low) % 12) for pc in CHORDS[name])


def root(name, low=38):
    return low + ((CHORDS[name][0] - low) % 12)


def fifth(name, low=38):
    return low + ((CHORDS[name][2] - low) % 12)


# ---------------------------------------------------------------- the song container

class Song:
    def __init__(self, name, bpm, bars):
        self.name, self.bpm, self.bars = name, bpm, bars
        self.parts = {}  # instrument -> list of (beat, beats, pitch, vel)

    def add(self, inst, notes, vel=90, gate=1.0):
        lst = self.parts.setdefault(inst, [])
        for beat, beats, p in notes:
            lst.append((beat, beats * gate, p, vel))

    def melody(self, inst, text, start_bar, vel=90, gate=1.0, octave=0):
        notes, _ = phrase(text, start_bar)
        self.add(inst, [(b, d, p + 12 * octave) for b, d, p in notes], vel, gate)

    @property
    def beats(self):
        return self.bars * 4


# General MIDI programs and channels for each instrument.
GM = {
    "marimba": (12, 0), "piano": (4, 1), "bass": (32, 2), "brass": (61, 3),
    "strings": (48, 4), "pizz": (45, 5), "drums": (0, 9),
}
DRUM = {"kick": 36, "snare": 38, "tom": 45, "rim": 37}


def write_midi(song, path):
    def vlq(n):
        out = [n & 0x7F]
        n >>= 7
        while n:
            out.insert(0, (n & 0x7F) | 0x80)
            n >>= 7
        return bytes(out)

    def track(events):
        events.sort(key=lambda e: (e[0], e[1]))
        data, last = b"", 0
        for tick, _order, msg in events:
            data += vlq(tick - last) + msg
            last = tick
        data += vlq(0) + b"\xff\x2f\x00"
        return b"MTrk" + struct.pack(">I", len(data)) + data

    tracks = []
    tempo = int(60_000_000 / song.bpm)
    meta = [(0, 0, b"\xff\x51\x03" + tempo.to_bytes(3, "big")),
            (0, 0, b"\xff\x58\x04\x04\x02\x18\x08"),
            (song.beats * PPQ, 0, b"\xff\x06\x04LOOP")]
    tracks.append(track(meta))
    for inst, notes in song.parts.items():
        prog, ch = GM["drums" if inst in DRUM else inst]
        name = inst.encode()
        ev = [(0, 0, b"\xff\x03" + bytes([len(name)]) + name)]
        if ch != 9:
            ev.append((0, 0, bytes([0xC0 | ch, prog])))
        for beat, beats, p, vel in notes:
            on = int(round(beat * PPQ))
            off = max(on + 1, int(round((beat + beats) * PPQ)))
            ev.append((on, 2, bytes([0x90 | ch, p, vel])))
            ev.append((off, 1, bytes([0x80 | ch, p, 0])))
        tracks.append(track(ev))
    with open(path, "wb") as f:
        f.write(b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), PPQ))
        for t in tracks:
            f.write(t)


# ---------------------------------------------------------------- the tiny synth

def hz(p):
    return 440.0 * 2 ** ((p - 69) / 12)


def env(n, attack, release_at, release, decay=None):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4))
    if decay:
        e *= np.exp(-t / decay)
    rel = np.clip((t - release_at) / release, 0, 1)
    return e * (1 - rel)


def wavetable(f, rolloff, phase):
    nh = max(1, int(9000 / f))
    k = np.arange(1, nh + 1)
    table_x = np.linspace(0, 1, 2048, endpoint=False)
    table = (np.sin(2 * np.pi * np.outer(k, table_x)) * (rolloff ** k / k)[:, None]).sum(0)
    table /= np.abs(table).max()
    return table[(phase * 2048).astype(np.int64) % 2048]


def voice(inst, p, secs, vel):
    f, a = hz(p), vel / 127.0
    if inst == "marimba":
        n = int(SR * 1.2)
        t = np.arange(n) / SR
        s = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.45) + 0.3 * np.sin(2 * np.pi * f * 3.93 * t) * np.exp(-t / 0.06)
        return a * s * env(n, 0.002, 9, 1)
    if inst == "piano":
        n = int(SR * (secs + 0.6))
        t = np.arange(n) / SR
        s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(4 * np.pi * f * t) * np.exp(-t / 0.4) + 0.1 * np.sin(6 * np.pi * f * t) * np.exp(-t / 0.2)
        return a * s * env(n, 0.004, secs, 0.5, decay=1.6)
    if inst in ("bass", "pizz"):
        plucked = inst == "pizz"
        n = int(SR * (secs + 0.25))
        t = np.arange(n) / SR
        s = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(4 * np.pi * f * t) + 0.15 * np.sin(6 * np.pi * f * t)
        return a * s * env(n, 0.006, secs, 0.12, decay=0.35 if plucked else 1.4)
    if inst == "brass":
        n = int(SR * (secs + 0.15))
        t = np.arange(n) / SR
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.25) / 0.3, 0, 1)
        ph = np.cumsum(f * vib / SR)
        bright = wavetable(f, 0.82, ph)
        dull = np.sin(2 * np.pi * ph)
        mix = np.clip(t / 0.06, 0, 1) * 0.6
        return a * (dull * (1 - mix) + bright * mix) * env(n, 0.035, secs, 0.12)
    if inst == "strings":
        n = int(SR * (secs + 0.5))
        t = np.arange(n) / SR
        s = sum(wavetable(f * d, 0.7, np.cumsum(np.full(n, f * d / SR)) + o) for d, o in ((1.0, 0), (1.004, 0.3), (0.996, 0.6))) / 3
        return a * s * env(n, 0.35, secs, 0.45)
    rng = np.random.default_rng(p * 1000 + int(vel))
    if inst == "snare":
        n = int(SR * 0.25)
        t = np.arange(n) / SR
        noise = np.diff(rng.standard_normal(n + 1))
        s = 0.5 * noise * np.exp(-t / 0.07) + 0.6 * np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.03)
        return a * s
    if inst == "rim":
        n = int(SR * 0.08)
        t = np.arange(n) / SR
        return a * 0.6 * np.sin(2 * np.pi * 1700 * t) * np.exp(-t / 0.012)
    if inst in ("kick", "tom"):
        lo, hi, d = (48, 110, 0.28) if inst == "kick" else (80, 150, 0.35)
        n = int(SR * 0.6)
        t = np.arange(n) / SR
        fr = lo + (hi - lo) * np.exp(-t / 0.04)
        return a * np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t / d)
    raise ValueError(inst)


LEVEL = {"marimba": 0.5, "piano": 0.22, "bass": 0.42, "pizz": 0.4, "brass": 0.34,
         "strings": 0.2, "snare": 0.22, "rim": 0.2, "kick": 0.45, "tom": 0.4}
PAN = {"marimba": 0.25, "piano": -0.3, "brass": -0.15, "strings": 0.0, "pizz": 0.2}


def render(song, path):
    spb = 60.0 / song.bpm
    n = int(round(song.beats * spb * SR))
    out = np.zeros((2, n))
    for inst, notes in song.parts.items():
        lvl = LEVEL[inst]
        pan = PAN.get(inst, 0.0)
        gains = (lvl * np.sqrt((1 - pan) / 2) * 1.41, lvl * np.sqrt((1 + pan) / 2) * 1.41)
        for beat, beats, p, vel in notes:
            s = voice(inst, p, beats * spb, vel)
            i0 = int(round(beat * spb * SR))
            idx = (np.arange(len(s)) + i0) % n  # tails wrap round: a seamless loop
            for c in range(2):
                np.add.at(out[c], idx, s * gains[c])
    # A small room: circular convolution, so the reverb wraps round too.
    rng = np.random.default_rng(7)
    ir_len = int(SR * 1.1)
    t = np.arange(ir_len) / SR
    wet = np.zeros_like(out)
    for c in range(2):
        ir = rng.standard_normal(ir_len) * np.exp(-t / 0.28)
        ir[: int(SR * 0.012)] = 0
        ir /= np.sqrt((ir ** 2).sum())
        irp = np.zeros(n)
        irp[:ir_len] = ir
        wet[c] = np.fft.irfft(np.fft.rfft(out[c]) * np.fft.rfft(irp), n)
    mix = out + 0.22 * wet
    mix = np.tanh(mix / np.abs(mix).max() * 1.1) / np.tanh(1.1) * 0.89
    pcm = (mix.T * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return n / SR


# ---------------------------------------------------------------- accompaniment patterns

def pads(song, inst, bars, start_bar, low, vel, every=4.0):
    for beat, beats, ch in chord_spans(bars, start_bar):
        b = beat
        while b < beat + beats - 1e-6:
            d = min(every, beat + beats - b)
            song.add(inst, [(b, d, p) for p in voicing(ch, low)], vel)
            b += d


def walking_bass(song, inst, bars, start_bar, vel, pattern, gate=1.0):
    """pattern: list of (beat in bar, beats, 'root'|'fifth'|'oct')."""
    spans = chord_spans(bars, start_bar)
    for i in range(len(bars)):
        for off, d, which in pattern:
            beat = (start_bar + i) * 4 + off
            ch = [c for b0, bl, c in spans if b0 <= beat < b0 + bl][0]
            p = {"root": root(ch), "fifth": fifth(ch), "oct": root(ch) + 12}[which]
            song.add(inst, [(beat, d, p)], vel, gate)


def drums(song, start_bar, bars, hits):
    """hits: list of (drum, beat in bar, vel)."""
    for i in range(bars):
        for drum, off, vel in hits:
            song.add(drum, [((start_bar + i) * 4 + off, 0.1, DRUM[drum])], vel)


# ---------------------------------------------------------------- the themes

BUILD_CHORDS = ["F", "Dm", "Bb", "C", "F", "Dm", "Gm", "C",
                "Bb", "C", "Am", "Dm", "Bb", "C", "F", "F",
                "F", "Dm", "Bb", "C", "F", "Am", "Gm C", "C7"]

BUILD_A = """r:1 C5:0.5 F5:0.5 A5:1 G5:1 | F5:1.5 D5:0.5 F5:1 r:1 | r:1 D5:0.5 F5:0.5 Bb5:1 A5:1 | G5:3 r:1 |
r:1 C5:0.5 F5:0.5 A5:1 C6:1 | D6:1.5 C6:0.5 A5:1 F5:1 | G5:1 Bb5:1 A5:1 G5:1 | E5:2 C5:1 r:1"""
BUILD_B = """D6:1 C6:0.5 Bb5:0.5 F5:2 | E5:0.5 F5:0.5 G5:1 C6:2 | C6:1 A5:0.5 G5:0.5 E5:2 | F5:1 E5:0.5 D5:0.5 A5:2 |
Bb5:1 A5:0.5 G5:0.5 F5:1 D5:1 | E5:1 G5:1 C6:1 Bb5:1 | A5:2 G5:0.5 F5:0.5 G5:1 | F5:3 r:1"""
BUILD_C = """r:1 C5:0.5 F5:0.5 A5:1 G5:1 | F5:1.5 D5:0.5 F5:1 r:1 | r:1 D5:0.5 F5:0.5 Bb5:1 A5:1 | G5:3 r:1 |
r:1 C5:0.5 F5:0.5 A5:1 C6:1 | C6:1.5 A5:0.5 E5:1 A5:1 | G5:1 Bb5:1 E5:1 G5:1 | E5:2 G5:1 r:1"""


def build_theme():
    s = Song("build", 96, 24)
    s.melody("marimba", BUILD_A, 0, 92)
    s.melody("marimba", BUILD_B, 8, 92)
    s.melody("marimba", BUILD_C, 16, 92)
    pads(s, "piano", BUILD_CHORDS, 0, 53, 60, every=2.0)
    walking_bass(s, "bass", BUILD_CHORDS, 0, 80, [(0, 1.8, "root"), (2, 0.9, "fifth"), (3, 0.9, "root")])
    drums(s, 0, 24, [("rim", 1, 40), ("rim", 3, 40)])
    return s


BATTLE_CHORDS = ["Dm", "Bb", "C", "Dm", "Dm", "Bb", "Gm", "A",
                 "Gm", "Dm", "Bb", "A", "Gm", "Dm", "Bb C", "A",
                 "Dm", "Bb", "C", "Dm", "Dm", "Bb", "Gm A", "A"]

BATTLE_A = """r:1 A4:0.5 D5:0.5 F5:1 E5:1 | D5:1.5 Bb4:0.5 D5:1 r:1 | r:1 C5:0.5 E5:0.5 G5:1 F5:1 | D5:3 r:1 |
r:1 A4:0.5 D5:0.5 F5:1 A5:1 | Bb5:1.5 A5:0.5 F5:1 D5:1 | G5:1 Bb5:1 A5:1 G5:1 | C#5:2 A4:1 r:1"""
BATTLE_B = """D5:1 Bb4:0.5 D5:0.5 G5:2 | F5:0.5 E5:0.5 D5:1 A5:2 | F5:1 D5:0.5 F5:0.5 Bb5:2 | A5:1 G5:0.5 F5:0.5 E5:2 |
G5:1 F5:0.5 E5:0.5 D5:1 Bb4:1 | A4:1 D5:1 F5:1 A5:1 | Bb5:1 A5:1 G5:1 E5:1 | E5:0.5 F5:0.5 E5:0.5 C#5:0.5 A4:2"""
BATTLE_C = """r:1 A4:0.5 D5:0.5 F5:1 E5:1 | D5:1.5 Bb4:0.5 D5:1 r:1 | r:1 C5:0.5 E5:0.5 G5:1 F5:1 | D5:3 r:1 |
r:1 A4:0.5 D5:0.5 F5:1 A5:1 | Bb5:1 A5:0.5 G5:0.5 F5:1 D5:1 | G5:1 Bb5:1 A5:1 E5:1 | C#5:1 E5:1 A4:1 r:1"""

MARCH = [("kick", 0, 90), ("snare", 0, 70), ("snare", 1, 45), ("snare", 1.5, 55), ("kick", 2, 80),
         ("snare", 2, 65), ("snare", 3, 45), ("snare", 3.5, 55), ("snare", 3.75, 45)]


def battle_theme():
    s = Song("battle", 108, 24)
    s.melody("brass", BATTLE_A, 0, 96, gate=0.72, octave=-1)
    s.melody("brass", BATTLE_B, 8, 96, gate=0.72, octave=-1)
    s.melody("brass", BATTLE_C, 16, 96, gate=0.72, octave=-1)
    pads(s, "strings", BATTLE_CHORDS, 0, 50, 70)
    walking_bass(s, "pizz", BATTLE_CHORDS, 0, 85,
                 [(0, 1, "root"), (1, 1, "root"), (2, 1, "root"), (3, 1, "fifth")], gate=0.6)
    drums(s, 0, 24, MARCH)
    return s


INTRO_CHORDS = (BATTLE_CHORDS[:8] + BUILD_CHORDS[:8]
                + ["Bb", "C", "F", "Dm", "Bb", "Gm", "C", "F"]
                + ["Dm", "Bb", "Gm", "A", "Dm", "Bb", "Gm", "A"])

INTRO_D = """D5:1 F5:1 Bb5:2 | C6:1.5 Bb5:0.5 G5:2 | A5:1 G5:0.5 F5:0.5 C5:2 | D5:1 F5:1 A5:2 |
Bb5:1.5 A5:0.5 G5:1 F5:1 | G5:1 Bb5:1 D6:2 | C6:1 Bb5:1 G5:1 E5:1 | F5:3 r:1"""
INTRO_E = """r:1 A4:0.5 D5:0.5 F5:1 A5:1 | Bb5:1.5 A5:0.5 F5:1 D5:1 | G5:1 Bb5:1 A5:1 G5:1 | C#5:2 A4:1 r:1 |
F5:2 E5:1 D5:1 | D5:2 F5:2 | G5:2 Bb5:1 A5:1 | E5:2 C#5:1 r:1"""


def intro_theme():
    s = Song("intro", 100, 32)
    # 1-8: the battle tune, broad and slow, on brass over held strings.
    s.melody("brass", BATTLE_A, 0, 88, octave=-1)
    pads(s, "strings", INTRO_CHORDS[:8], 0, 50, 64)
    walking_bass(s, "bass", INTRO_CHORDS[:8], 0, 70, [(0, 3.8, "root")])
    drums(s, 0, 8, [("tom", 0, 70)])
    # 9-16: the build tune on marimba, a light snare underneath.
    s.melody("marimba", BUILD_A, 8, 92)
    pads(s, "piano", INTRO_CHORDS[8:16], 8, 53, 58, every=2.0)
    walking_bass(s, "bass", INTRO_CHORDS[8:16], 8, 78, [(0, 1.8, "root"), (2, 0.9, "fifth"), (3, 0.9, "root")])
    drums(s, 8, 8, [("snare", 1, 35), ("snare", 3, 35), ("snare", 3.5, 25)])
    # 17-24: its own tune, everyone together.
    s.melody("brass", INTRO_D, 16, 92, octave=-1)
    s.melody("marimba", INTRO_D, 16, 80)
    pads(s, "strings", INTRO_CHORDS[16:24], 16, 53, 72)
    walking_bass(s, "bass", INTRO_CHORDS[16:24], 16, 82, [(0, 1.8, "root"), (2, 1.8, "fifth")])
    drums(s, 16, 8, MARCH)
    # 25-32: winding back down to D minor, ready to loop.
    s.melody("brass", INTRO_E, 24, 84, octave=-1)
    pads(s, "strings", INTRO_CHORDS[24:32], 24, 50, 62)
    walking_bass(s, "bass", INTRO_CHORDS[24:32], 24, 70, [(0, 3.8, "root")])
    drums(s, 24, 4, [("snare", 0, 50), ("snare", 2, 40), ("snare", 3.5, 35)])
    drums(s, 28, 4, [("tom", 0, 60)])
    return s


if __name__ == "__main__":
    for song in (build_theme(), battle_theme(), intro_theme()):
        base = os.path.join(HERE, song.name + "_theme")
        write_midi(song, base + ".mid")
        secs = render(song, base + ".wav")
        print(f"{song.name}: {song.bars} bars at {song.bpm} bpm, {secs:.1f} s loop -> {base}.mid / .wav")
