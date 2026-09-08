#!/usr/bin/env bash
# Kiosk playback of the Scripps Pier cam. Re-resolves the signed URL on every
# restart, and forces a restart before the ~12h token expiry so a long-running
# player never dies on a 403 mid-stream.
set -uo pipefail
cd "$(dirname "$0")"

RESTART_AFTER="${RESTART_AFTER:-21600}"   # 6h, comfortably inside token life

# On a Lite install there is no X server, so render straight to KMS/DRM.
if [ -z "${DISPLAY:-}" ] && [ -e /dev/dri/card0 ]; then
  VO_ARGS=(--vo=gpu --gpu-context=drm)
else
  VO_ARGS=(--fullscreen)
fi

# Pi 3's VideoCore IV hardware H.264 decoder. Must be named explicitly:
# --hwdec=auto-safe excludes v4l2m2m and falls back to software (~0.95x realtime,
# i.e. dropping frames). Override with HWDEC=no to compare.
HWDEC="${HWDEC:-v4l2m2m-copy}"

while true; do
  if ! URL=$(./resolve_url.sh); then
    echo "$(date -Is) could not resolve stream URL; retrying in 30s" >&2
    sleep 30
    continue
  fi
  echo "$(date -Is) starting player" >&2

  mpv "$URL" \
    "${VO_ARGS[@]}" \
    --no-audio \
    --no-osc --osd-level=0 --no-input-default-bindings \
    --cursor-autohide=always \
    --profile=low-latency \
    --hwdec="$HWDEC" \
    --panscan=1.0 \
    --keep-open=no \
    --input-ipc-server=/tmp/mpv-pierviz.sock \
    --msg-level=all=warn &

  PID=$!
  ( sleep "$RESTART_AFTER"; kill "$PID" 2>/dev/null ) &
  TIMER=$!

  wait "$PID"
  kill "$TIMER" 2>/dev/null
  echo "$(date -Is) player exited; respawning" >&2
  sleep 2
done
