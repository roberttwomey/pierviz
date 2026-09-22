#!/usr/bin/env bash
# Kiosk playback of the Scripps Pier cam. Re-resolves the signed URL on every
# restart, and forces a restart before the ~12h token expiry so a long-running
# player never dies on a 403 mid-stream.
set -uo pipefail
cd "$(dirname "$0")"

RESTART_AFTER="${RESTART_AFTER:-21600}"   # 6h, comfortably inside token life
BACKOFF=2

# On a Lite install there is no X server, so render straight to KMS/DRM.
#
# --vo=gpu-next (libplacebo) is the only output here that accepts the zero-copy
# DRM prime buffers the hardware decoder produces. Measured on a Pi 4 at
# 1080p60: 11.3% CPU with zero dropped frames, against 311% for --vo=drm
# (which mpv itself documents as "software scaling") and 54% dropped frames for
# plain --vo=gpu. See README.
#
# The mode must be pinned. Left to itself mpv takes the display's preferred
# mode, and a 4K TV offers 3840x2160 -- four times the pixels, for a 1080p
# stream the TV will upscale for free anyway. On a Pi 4 that alone drops
# playback to 0.17x realtime.
if [ -z "${DISPLAY:-}" ] && [ -e /dev/dri/card0 ]; then
  # The v3d render node also appears as a DRM card and cannot drive a display,
  # so pick whichever card actually owns the HDMI connectors.
  DRM_CARD=$(ls -d /sys/class/drm/card*-HDMI-* 2>/dev/null | head -1 \
             | xargs -r basename | cut -d- -f1)
  DRM_CARD="${DRM_CARD:-card0}"
  VO_ARGS=(--vo=gpu-next --gpu-context=drm
           --drm-device="/dev/dri/$DRM_CARD"
           --drm-mode="${DRM_MODE:-1920x1080@60}")
else
  VO_ARGS=(--fullscreen)
fi

# Name the V4L2 decoder explicitly: --hwdec=auto-safe excludes it and falls
# back to software. Use v4l2m2m (zero-copy), NOT v4l2m2m-copy -- the copy pulls
# every frame out to CPU memory and back, which costs ~65% CPU here and 300%+
# with a software-scaling VO. A Pi 5 has no H.264 block at all: use HWDEC=no.
HWDEC="${HWDEC:-v4l2m2m}"

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
