"""Compose an original, loopable instrumental for the fighting game."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parents[1] / "assets" / "audio" / "battle_theme.wav"
SR = 22050
BPM = 132
BEAT = 60 / BPM
BARS = 16
LENGTH = BARS * 4 * BEAT
N = round(LENGTH * SR)
left = np.zeros(N, dtype=np.float64)
right = np.zeros(N, dtype=np.float64)
rng = np.random.default_rng(271029)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def add(signal, start, pan=0.0, gain=1.0):
    i = round(start * SR)
    if i >= N:
        return
    m = min(len(signal), N - i)
    left[i:i+m] += signal[:m] * gain * np.sqrt((1 - pan) / 2)
    right[i:i+m] += signal[:m] * gain * np.sqrt((1 + pan) / 2)


def synth(midi, length, kind="lead"):
    t = np.arange(round(length * SR)) / SR
    f = hz(midi)
    if kind == "pad":
        wave_data = np.sin(2*np.pi*f*t) + 0.22*np.sin(2*np.pi*2*f*t)
        attack = np.minimum(1.0, t / 0.10)
        release = np.minimum(1.0, (length-t) / 0.14)
        env = np.minimum(attack, release)
    elif kind == "bass":
        wave_data = np.sin(2*np.pi*f*t) + 0.24*np.sin(2*np.pi*2*f*t)
        env = (1-np.exp(-t*90)) * np.exp(-t*3.1)
    elif kind == "arp":
        wave_data = np.sin(2*np.pi*f*t) + 0.19*np.sin(2*np.pi*3*f*t)
        env = (1-np.exp(-t*180)) * np.exp(-t*9.0)
    else:
        wave_data = (np.sin(2*np.pi*f*t) + 0.34*np.sin(2*np.pi*2*f*t)
                     + 0.13*np.sin(2*np.pi*3*f*t))
        env = (1-np.exp(-t*75)) * np.minimum(1.0, (length-t)/0.07)
    return wave_data * env


def kick():
    t = np.arange(round(0.32*SR))/SR
    phase = 2*np.pi*(57*t + 92*(1-np.exp(-t*39))/39)
    return np.sin(phase)*np.exp(-t*16)*0.62


def snare():
    t = np.arange(round(0.18*SR))/SR
    n = rng.normal(0, 1, len(t))
    return (n*0.28 + np.sin(2*np.pi*185*t)*0.18)*np.exp(-t*26)


def hat(open_hat=False):
    length = 0.27 if open_hat else 0.085
    t = np.arange(round(length*SR))/SR
    n = rng.normal(0, 1, len(t))
    hp = n - np.convolve(n, np.ones(19)/19, mode="same")
    return hp*np.exp(-t*(20 if open_hat else 65))*0.10


chords = [
    ([50, 53, 57], 38),  # D minor
    ([46, 50, 53], 34),  # B flat
    ([53, 57, 60], 41),  # F major
    ([48, 52, 55], 36),  # C major
]
melody = [
    [(0, 69, .48), (.75, 72, .48), (1.5, 74, .72), (2.5, 72, .45), (3.25, 69, .55)],
    [(0, 65, .48), (.75, 69, .48), (1.5, 70, .72), (2.5, 69, .45), (3.25, 65, .55)],
    [(0, 72, .48), (.75, 76, .48), (1.5, 77, .72), (2.5, 76, .45), (3.25, 72, .55)],
    [(0, 67, .48), (.75, 72, .48), (1.5, 76, .72), (2.5, 72, .45), (3.25, 67, .55)],
]

for bar in range(BARS):
    chord, root = chords[bar % 4]
    base = bar*4*BEAT
    for note in chord:
        add(synth(note, 4*BEAT, "pad"), base, pan=-0.35+(note-chord[0])*.1, gain=.052)
    for beat, note in [(0, root), (1.5, root+7), (2, root), (3.5, root+7)]:
        add(synth(note, .40, "bass"), base+beat*BEAT, pan=0, gain=.19)
    for eighth in range(8):
        note = chord[(eighth + (bar//4)) % 3] + 12
        add(synth(note, .23, "arp"), base+eighth*.5*BEAT, pan=(-.28 if eighth%2 else .28), gain=.07)
    for beat in [0, 2]:
        add(kick(), base+beat*BEAT, gain=1.0)
    for beat in [1, 3]:
        add(snare(), base+beat*BEAT, gain=.88)
    for eighth in range(8):
        add(hat(open_hat=eighth==7 and bar%4==3), base+eighth*.5*BEAT,
            pan=(-.2 if eighth%2 else .2), gain=.9 if eighth%2 else 1.0)
    for beat, note, beats in melody[bar%4]:
        if bar%8 >= 4 and beat==3.25:
            note += 12
        add(synth(note, beats*BEAT, "lead"), base+beat*BEAT, pan=.12, gain=.13)

# Preserve musical bar alignment while smoothing the loop seam.
fade = round(.025*SR)
left[:fade] *= np.linspace(0, 1, fade)
right[:fade] *= np.linspace(0, 1, fade)
left[-fade:] *= np.linspace(1, 0, fade)
right[-fade:] *= np.linspace(1, 0, fade)
peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
stereo = np.stack([left, right], axis=1) * (0.78/max(peak, 1e-9))
pcm = (np.clip(stereo, -1, 1)*32767).astype(np.int16)
with wave.open(str(OUT), "wb") as file:
    file.setnchannels(2)
    file.setsampwidth(2)
    file.setframerate(SR)
    file.writeframes(pcm.tobytes())
print(OUT.name, round(N/SR, 2), "seconds", OUT.stat().st_size, "bytes")
