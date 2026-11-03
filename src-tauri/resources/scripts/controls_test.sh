#!/bin/bash
# Reads the built-in controller and prints one JSON line per press for the
# Controls test. Stops when the app closes stdin, or after 10 minutes.

read -r -d '' PY <<'EOF'
import glob, json, os, select, struct, sys, time

# (byte, bit) in the Deck controller input report
BITS = {
    (8, 7): "A", (8, 5): "B", (8, 6): "X", (8, 4): "Y",
    (9, 0): "DUP", (9, 1): "DRIGHT", (9, 3): "DDOWN", (9, 2): "DLEFT",
    (8, 3): "L1", (8, 2): "R1", (8, 1): "L2", (8, 0): "R2",
    (13, 1): "L4", (9, 7): "L5", (13, 2): "R4", (10, 0): "R5",
    (9, 4): "VIEW", (9, 6): "MENU", (14, 2): "QAM", (9, 5): "STEAM",
    (10, 6): "L3", (11, 2): "R3", (13, 6): "LS_TOUCH", (13, 7): "RS_TOUCH",
    (10, 3): "LPAD_TOUCH", (10, 1): "LPAD_CLICK",
    (10, 4): "RPAD_TOUCH", (10, 2): "RPAD_CLICK",
}
# (offset, name when pushed positive, name when pushed negative)
STICKS = [(48, "LS_RIGHT", "LS_LEFT"), (50, "LS_UP", "LS_DOWN"),
          (52, "RS_RIGHT", "RS_LEFT"), (54, "RS_UP", "RS_DOWN")]
TRIGGERS = [(44, "L2"), (46, "R2")]
PUSH = 20000


def out(obj):
    try:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        sys.exit(0)


devs = []
for uevent in glob.glob("/sys/class/hidraw/hidraw*/device/uevent"):
    try:
        if "000028DE:00001205" in open(uevent).read().upper():
            devs.append("/dev/" + uevent.split("/")[4])
    except OSError:
        pass
fds = []
for dev in sorted(devs):
    try:
        fds.append(os.open(dev, os.O_RDONLY | os.O_NONBLOCK))
    except OSError:
        pass
if not fds:
    out({"type": "error", "message": "The built-in controller was not found or could not be read."})
    sys.exit(1)
out({"type": "ready"})

held = set()
deadline = time.time() + 600
while time.time() < deadline:
    ready, _, _ = select.select(fds + [0], [], [], 1.0)
    if 0 in ready and not os.read(0, 4096):
        sys.exit(0)
    for fd in ready:
        if fd == 0:
            continue
        try:
            d = os.read(fd, 64)
        except OSError:
            continue
        if len(d) != 64 or d[2] != 0x09:
            continue
        now = set()
        for (byte, bit), name in BITS.items():
            if d[byte] & (1 << bit):
                now.add(name)
        for off, pos, neg in STICKS:
            v = struct.unpack_from("<h", d, off)[0]
            if v > PUSH:
                now.add(pos)
            elif v < -PUSH:
                now.add(neg)
        for off, name in TRIGGERS:
            if struct.unpack_from("<H", d, off)[0] > PUSH:
                now.add(name)
        for name in sorted(now - held):
            out({"type": "press", "id": name})
        held = now
EOF

exec python3 -u -c "$PY"
