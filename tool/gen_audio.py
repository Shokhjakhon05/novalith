#!/usr/bin/env python3
"""Synthesises every sound in Novalith from maths - no samples, no third-party recordings, so
there is nothing to license. Run: python3 tool/gen_audio.py (needs ffmpeg for the music loop)."""
import math
import os
import random
import struct
import subprocess
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'audio')
SR = 44100
TAU = 2 * math.pi


def write(name, samples, sr=SR):
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = min(1.0, 0.89 / peak)
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s * gain)) * 32767)) for s in samples))
    print('wrote', name, f'{len(samples) / sr:.2f}s')
    return path


def tone(freq, dur, partials=((1, 1.0),), decay=6.0, attack=0.004, vibrato=0.0):
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        env = min(1.0, t / attack) * math.exp(-decay * t)
        v = 0.0
        for mult, amp in partials:
            f = freq * mult * (1 + vibrato * math.sin(TAU * 5 * t))
            v += amp * math.sin(TAU * f * t) * math.exp(-mult * 0.6 * t * decay / 6)
        out.append(v * env)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def delay(track, seconds):
    return [0.0] * int(seconds * SR) + track


def scale(track, k):
    return [v * k for v in track]


def noise(dur, decay, lowpass=0.2, seed=1):
    rnd = random.Random(seed)
    n = int(dur * SR)
    out = []
    y = 0.0
    for i in range(n):
        t = i / SR
        y += lowpass * (rnd.uniform(-1, 1) - y)
        out.append(y * math.exp(-decay * t))
    return out


def sweep(f0, f1, dur, decay=4.0):
    n = int(dur * SR)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = f0 * (f1 / f0) ** (t / dur)
        phase += TAU * f / SR
        out.append(math.sin(phase) * math.exp(-decay * t) * min(1.0, t / 0.003))
    return out


BELL = ((1, 1.0), (2, 0.42), (3, 0.16), (4.2, 0.07))


def main():
    os.makedirs(OUT, exist_ok=True)

    # Merge notes: a major pentatonic ladder. Each further step of a chain plays the next note,
    # so a combo is heard as a rising melody.
    ladder = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.51]
    for i, f in enumerate(ladder):
        write(f'merge_{i}.wav', mix(tone(f, 0.42, BELL, decay=7.5), scale(sweep(f * 0.5, f, 0.05, 30), 0.35)))

    write('drop.wav', mix(scale(sweep(520, 240, 0.09, 26), 0.8), scale(noise(0.06, 50, 0.5), 0.25)))
    write('impact.wav', mix(sweep(150, 62, 0.16, 20), scale(noise(0.05, 70, 0.3, 3), 0.5)))
    write('tap.wav', mix(scale(tone(1320, 0.05, ((1, 1.0), (2, 0.3)), decay=70), 0.8)))

    write('big.wav', mix(tone(261.63, 0.9, BELL, decay=3.6), tone(392.0, 0.9, BELL, decay=3.8),
                         tone(523.25, 0.9, BELL, decay=4.0), scale(sweep(110, 42, 0.5, 6), 0.9),
                         scale(noise(0.35, 9, 0.12, 5), 0.5)))

    bang = mix(scale(sweep(70, 26, 2.2, 1.6), 1.1), scale(noise(2.2, 1.9, 0.07, 9), 0.9),
               delay(tone(261.63, 1.8, BELL, decay=1.8), 0.05), delay(tone(329.63, 1.8, BELL, decay=1.8), 0.11),
               delay(tone(392.0, 1.8, BELL, decay=1.8), 0.17), delay(tone(523.25, 1.8, BELL, decay=1.7), 0.23),
               delay(tone(1046.5, 1.6, BELL, decay=2.0), 0.32))
    write('bigbang.wav', bang)

    write('perfect.wav', mix(tone(1318.51, 0.2, BELL, decay=14), delay(tone(1567.98, 0.2, BELL, decay=14), 0.055),
                             delay(tone(2093.0, 0.32, BELL, decay=10), 0.11)))
    write('coin.wav', mix(tone(987.77, 0.12, BELL, decay=16), delay(tone(1318.51, 0.3, BELL, decay=9), 0.07)))
    write('unlock.wav', mix(*[delay(tone(f, 0.5, BELL, decay=6), i * 0.075)
                              for i, f in enumerate([523.25, 659.25, 783.99, 1046.5, 1318.51])]))
    write('record.wav', mix(*[delay(tone(f, 0.7, BELL, decay=4.2), d)
                              for f, d in [(523.25, 0), (659.25, 0.1), (783.99, 0.2), (1046.5, 0.34), (783.99, 0.34), (1318.51, 0.34)]]))
    write('danger.wav', mix(tone(98.0, 0.5, ((1, 1.0), (2, 0.5), (3, 0.2)), decay=5, attack=0.03),
                            delay(tone(92.5, 0.4, ((1, 1.0), (2, 0.5)), decay=6, attack=0.03), 0.18)))
    write('gameover.wav', mix(*[delay(tone(f, 0.9, BELL, decay=3.2), d)
                                for f, d in [(392.0, 0), (329.63, 0.16), (261.63, 0.32), (196.0, 0.5)]],
                              scale(sweep(120, 40, 1.0, 3), 0.6)))

    music()


def music():
    """A slow ambient pad that loops seamlessly: every voice is periodic over the loop length."""
    sr = 22050
    chord_len = 8.0
    chords = [
        [110.0, 164.81, 220.0, 261.63, 329.63],   # A minor
        [87.31, 130.81, 174.61, 220.0, 261.63],   # F major
        [130.81, 196.0, 261.63, 329.63, 392.0],   # C major
        [98.0, 146.83, 196.0, 246.94, 293.66],    # G major
    ]
    total = chord_len * len(chords)
    n = int(total * sr)
    out = [0.0] * n
    fade = 2.6
    for ci, chord in enumerate(chords):
        start = ci * chord_len
        for vi, f in enumerate(chord):
            amp = 0.34 / (1 + vi * 0.35)
            det = 1 + 0.0016 * (vi - 2)
            span = int((chord_len + fade) * sr)
            for k in range(span):
                t = k / sr
                env = min(1.0, t / fade) * min(1.0, (chord_len + fade - t) / fade)
                env = env * env * (3 - 2 * env)
                trem = 0.86 + 0.14 * math.sin(TAU * (0.11 + 0.03 * vi) * t + vi)
                v = math.sin(TAU * f * t) + 0.5 * math.sin(TAU * f * det * t + 1.3) + 0.12 * math.sin(TAU * 2 * f * t)
                out[(int(start * sr) + k) % n] += v * amp * env * trem
    # Sparse high sparkles, placed deterministically.
    rnd = random.Random(11)
    for _ in range(26):
        at = rnd.uniform(0, total)
        f = rnd.choice([659.25, 783.99, 880.0, 1046.5, 1318.51])
        for k in range(int(1.6 * sr)):
            t = k / sr
            out[(int(at * sr) + k) % n] += 0.07 * math.sin(TAU * f * t) * math.exp(-3.2 * t) * min(1.0, t / 0.01)
    wav = write('_music.wav', out, sr)
    ogg = os.path.join(OUT, 'music.ogg')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libvorbis', '-q:a', '3', ogg], check=True)
    os.remove(wav)
    print('wrote music.ogg', os.path.getsize(ogg) // 1024, 'KB')


if __name__ == '__main__':
    main()
