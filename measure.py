#!/usr/bin/env python3
"""Report what the running player is actually doing.

Rate alone is misleading: mpv holds 1.00x by dropping frames, so a perfect
rate is equally consistent with smooth playback and with discarding most
frames. Always read rate and drop rate together.

Usage: ./measure.py [seconds]   (default 30)
"""
import json
import os
import socket
import statistics
import subprocess
import sys
import time

SOCK = os.environ.get("MPV_SOCK", "/tmp/mpv-pierviz.sock")


def query(props):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(SOCK)
    f = s.makefile("rw")
    out = {}
    for i, p in enumerate(props):
        f.write(json.dumps({"command": ["get_property", p], "request_id": i}) + "\n")
        f.flush()
        while True:
            line = f.readline()
            if not line:
                break
            m = json.loads(line)
            if m.get("request_id") == i:
                out[p] = m.get("data")
                break
    s.close()
    return out


def cpu_of(name="mpv"):
    try:
        pid = subprocess.check_output(["pgrep", "-x", name]).split()[0].decode()
        out = subprocess.check_output(
            ["top", "-b", "-n2", "-d", "3", "-p", pid], stderr=subprocess.DEVNULL
        ).decode()
        rows = [l for l in out.splitlines() if l.strip().startswith(pid)]
        return float(rows[-1].split()[8]) if rows else None
    except Exception:
        return None


def main():
    dur = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    props = ["time-pos", "frame-drop-count", "vo-delayed-frame-count",
             "hwdec-current", "display-fps", "container-fps"]

    a = query(props)
    fps = a.get("container-fps") or 30.0
    rates = []
    t_prev, w_prev = a["time-pos"], time.time()
    for _ in range(dur):
        time.sleep(1)
        b = query(["time-pos"])
        now = time.time()
        rates.append((b["time-pos"] - t_prev) / (now - w_prev))
        t_prev, w_prev = b["time-pos"], now
    b = query(props)

    elapsed = w_prev - time.time() + dur
    dropped = b["frame-drop-count"] - a["frame-drop-count"]
    expected = fps * dur

    print("hwdec       : %s" % b["hwdec-current"])
    print("display     : %.4g Hz, content %.4g fps" % (b["display-fps"] or 0, fps))
    print("rate        : mean %.3fx  stdev %.3f  min %.2fx" % (
        statistics.mean(rates), statistics.stdev(rates), min(rates)))
    print("frames      : %d dropped of ~%d expected  (%.1f%%)" % (
        dropped, expected, 100.0 * dropped / expected))
    print("vo delayed  : %d" % (b["vo-delayed-frame-count"] - a["vo-delayed-frame-count"]))
    cpu = cpu_of()
    print("mpv CPU     : %s" % ("%.1f%%" % cpu if cpu else "?"))
    try:
        print("temp        : %s" % subprocess.check_output(
            ["vcgencmd", "measure_temp"]).decode().strip().split("=")[1])
        print("throttled   : %s" % subprocess.check_output(
            ["vcgencmd", "get_throttled"]).decode().strip().split("=")[1])
    except Exception:
        pass

    mean = statistics.mean(rates)
    problems = []
    if dropped > expected * 0.01:
        problems.append("dropping %.0f%% of frames" % (100.0 * dropped / expected))
    if not 0.97 <= mean <= 1.03:
        problems.append("rate %.2fx (should be ~1.00x)" % mean)
    print("verdict     : %s" % ("OK" if not problems else " AND ".join(problems)))


if __name__ == "__main__":
    main()
