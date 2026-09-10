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
- **Use `--vo=drm`, not `--vo=gpu`.** VideoCore IV has no usable GL path here
  (mpv logs "High bit depth FBOs unsupported. Enabling dumb mode."), and the
  software fallback renders at ~0.39x realtime. Playback then falls behind the
  live edge and jumps forward every ~26s. Measured via the IPC socket: position
  advancing +3.90s per 10s of wall clock, punctuated by +10/+20s catch-up jumps.
  Note `frame-drop-count` stays 0 throughout -- with no audio track mpv never
  engages drop logic, so the counter hides the fault. Measure the rate instead.
- **Zero-copy `--hwdec=v4l2m2m` is worse than `v4l2m2m-copy` here** -- tested
  on the real display: 0.70x vs 0.98x. The decoder's frames are not in a form
  the DRM plane takes directly (mpv warns "Failed to create HW uploader for
  format yuv420p"), so a conversion pass costs more than the copy it saves.
  Do not retry this.
- `--profile=low-latency` is wrong for a wall display: it sets a 4KiB stream
  buffer, `cache-pause=no` (jump rather than wait) and `video-sync=audio` on a
  stream with no audio. Latency is irrelevant here; smoothness is not.
- The source playlist holds only 3 x 10s segments (30s). That is a tight window
  with little margin, so anything that falls behind gets forced into a skip.
  The source itself is healthy: segments arrive every 10.0s with contiguous PTS
  and exactly 300 frames each.
- The Pi 3B+ soft-throttles at 60C, dropping 1.4GHz to 1.2GHz. In a hot room it
  will sit there permanently; a heatsink is worth more than any software change.
- Change `STREAM` in `resolve_url.sh` to point at a different HDOnTap cam.

## Deployed

Running on a Pi 3B+ (Debian 13 Trixie Lite, arm64) at `streaming.local` as
`jasper`, from `~/work/pierviz/`, via `pierviz.service` (enabled at boot).
Query the live player: `python3 /tmp/mpvq.py frame-drop-count hwdec-current`

## Future development

**Web interface on the Pi.** Serve a small control page from `streaming.local`
so a phone, tablet, or laptop on the same network can drive the display without
SSH. It would talk to the running player over the mpv IPC socket
(`/tmp/mpv-pierviz.sock`), which `play_loop.sh` already opens.

**Feed picker.** Let that page switch between several cams rather than the one
hardcoded stream — surf or underwater, and not only San Diego. Candidates:

- Scripps Pier underwater (HDOnTap) — the current feed, already working
- Surfline, Scripps Pier —
  https://www.surfline.com/surf-report/scripps/5842041f4e65fad6a7708839?camId=5cf9cab8d23ea6772d19cddf
- Surfline, La Jolla Shores —
  https://www.surfline.com/surf-report/la-jolla-shores/5842041f4e65fad6a77088cc?camId=58349b9b3421b20545c4b54d
- Australia and elsewhere — TBD

Worth knowing before starting: **each provider resolves differently.** The
HDOnTap path solved here (public embed endpoint returning a signed URL to plain
curl) does not generalize. Surfline cams sit behind an account, and their
resolution flow is its own integration with its own access terms. Plan for a
resolver per provider behind a common interface — `resolve_url.sh` becomes one
implementation of that interface rather than the only one — and expect the feed
list to carry credentials or entitlements for some sources but not others.
