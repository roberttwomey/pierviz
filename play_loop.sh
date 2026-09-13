#!/usr/bin/env bash
# Kiosk playback of the Scripps Pier cam. Re-resolves the signed URL on every
# restart, and forces a restart before the ~12h token expiry so a long-running
# player never dies on a 403 mid-stream.
set -uo pipefail
cd "$(dirname "$0")"

RESTART_AFTER="${RESTART_AFTER:-21600}"   # 6h, comfortably inside token life
BACKOFF=2

# On a Lite install there is no X server, so render straight to KMS/DRM.
# Use --vo=drm (direct DRM plane), NOT --vo=gpu: VideoCore IV has no usable GL
# path here ("High bit depth FBOs unsupported. Enabling dumb mode."), and the
# software fallback renders ~0.39x realtime, so playback falls behind live and
# jumps forward every ~26s to catch up.
if [ -z "${DISPLAY:-}" ] && [ -e /dev/dri/card0 ]; then
  VO_ARGS=(--vo=drm)
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
  START=$(date +%s)

  mpv "$URL" \
    "${VO_ARGS[@]}" \
    --no-audio \
    --no-osc --osd-level=0 --no-input-default-bindings \
    --cursor-autohide=always \
    --cache=yes \
    --stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_on_http_error=4xx\,5xx,reconnect_delay_max=30 \
    --demuxer-readahead-secs=25 \
    --hwdec="$HWDEC" \
    --keep-open=no \
    --input-ipc-server=/tmp/mpv-pierviz.sock \
    --msg-level=all=warn &

  PID=$!
  ( sleep "$RESTART_AFTER"; kill "$PID" 2>/dev/null ) &
  TIMER=$!

  wait "$PID"
  kill "$TIMER" 2>/dev/null

  # A player that dies within a minute of starting is failing, not finishing
  # (the Pi 3B+ SDIO wifi drops out under sustained load). Back off instead of
  # respawning every 2s, which turns one outage into a visible crash loop.
  RAN=$(( $(date +%s) - START ))
  if [ "$RAN" -lt 60 ]; then
    BACKOFF=$(( BACKOFF < 2 ? 2 : BACKOFF * 2 ))
    [ "$BACKOFF" -gt 60 ] && BACKOFF=60
  else
    BACKOFF=2
  fi
  echo "$(date -Is) player exited after ${RAN}s; respawning in ${BACKOFF}s" >&2
  sleep "$BACKOFF"
done
