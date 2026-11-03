#!/bin/bash
# Plays a short tone on one built-in speaker.
# Usage: speaker_test.sh left|right

set -u
SIDE="${1:-left}"
case "$SIDE" in
  left|right) ;;
  *) echo "Unknown side: $SIDE" >&2; exit 2 ;;
esac

SINK=$(pactl list short sinks 2>/dev/null | awk '/Speaker/{print $2; exit}')
if [[ -z "$SINK" ]]; then
  echo "Speakers not found." >&2
  exit 1
fi

WAV=$(mktemp --suffix=.wav)
python3 - "$WAV" "$SIDE" <<'PY'
import math, struct, sys, wave
path, side = sys.argv[1], sys.argv[2]
rate, secs, freq = 48000, 1.5, 660
frames = bytearray()
for i in range(int(rate * secs)):
    t = i / rate
    fade = min(1.0, t / 0.05, (secs - t) / 0.05)
    v = int(0.4 * 32767 * fade * math.sin(2 * math.pi * freq * t))
    frames += struct.pack("<hh", v if side == "left" else 0, v if side == "right" else 0)
with wave.open(path, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(rate)
    w.writeframes(bytes(frames))
PY

pw-play --target "$SINK" "$WAV"
code=$?
rm -f "$WAV"
if [[ $code -eq 0 ]]; then
  echo "Played a tone on the $SIDE speaker."
else
  echo "Could not play the tone (pw-play exit $code)." >&2
fi
exit $code
