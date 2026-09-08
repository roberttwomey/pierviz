# Scripps Pier cam → Samsung Frame TV

The page at https://coollab.ucsd.edu/pierviz/ embeds an HDOnTap player. The
underlying stream is:

    https://live.hdontap.com/hls/hosb6lo/scripps_pier-underwater.stream/playlist.m3u8?t=<token>&e=<expiry>

1080p H.264, ~30fps, **no audio track**.

## The catch

That URL is signed and expires in about 12 hours, so it cannot be hardcoded.
`resolve_url.sh` re-fetches a fresh one from HDOnTap's public embed endpoint
(plain curl, no cookies or browser needed).

## Two routes

**Live video** — `play_loop.sh` + `pierviz.service` on a Pi or any small box on
HDMI. Re-resolves the URL on every restart and force-restarts every 6h so the
player never dies on an expired token. The TV sits on the HDMI input; Art Mode
is not reachable while an HDMI source is live.

**Art Mode stills** — `frame_art.py` grabs one frame and uploads it as art over
the network. Not live motion, but it lives in the Frame's normal art rotation
with no box attached to the TV. Run it on a timer.

## Notes

- `omxplayer` from the old Pi scripts is gone on current Pi OS; mpv replaces it.
- **`--hwdec=auto-safe` does not work on a Pi.** mpv classifies the V4L2 wrapper
  as unsafe for auto-selection, so it probes CUDA/Vulkan, fails, and silently
  falls back to software decode (0.945x realtime on a 3B+ = continuous dropped
  frames). Name `v4l2m2m-copy` explicitly. Verified: hardware decode runs at
  1.99x with zero dropped frames.
- On a Lite install there is no X server, so the player renders straight to
  KMS/DRM. The user must be in the `video` and `render` groups.
- The Pi 3B+ soft-throttles at 60C, dropping 1.4GHz to 1.2GHz. In a hot room it
  will sit there permanently; a heatsink is worth more than any software change.
- Change `STREAM` in `resolve_url.sh` to point at a different HDOnTap cam.

## Deployed

Running on a Pi 3B+ (Debian 13 Trixie Lite, arm64) at `streaming.local` as
`jasper`, from `~/work/pierviz/`, via `pierviz.service` (enabled at boot).
Query the live player: `python3 /tmp/mpvq.py frame-drop-count hwdec-current`
