#!/usr/bin/env python3
"""Push a fresh still from the Scripps Pier cam into The Frame's Art Mode.

Art Mode cannot play third-party video, so this grabs one frame, crops it to
the panel's 16:9, and uploads it as art. Run it on a timer (cron/launchd) to
get a slowly-updating pier "painting". Each run replaces the previously
uploaded frame so the TV's art library does not grow without bound.

Setup:  pip install "git+https://github.com/NickWaterton/samsung-tv-ws-api.git#egg=samsungtvws[async,encrypted]"
Usage:  ./frame_art.py --host 192.168.1.50
"""
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

STATE = Path(__file__).with_name(".last_art_id")


def grab_frame(dest: Path) -> None:
    """Pull one frame from the live stream via the sibling resolver."""
    url = subprocess.run(
        [str(Path(__file__).with_name("resolve_url.sh"))],
        capture_output=True, text=True, check=True,
    ).stdout.strip()

    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", url,
         "-frames:v", "1", "-q:v", "2", str(dest)],
        check=True,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True, help="Frame TV IP address")
    ap.add_argument("--matte", default="none", help="Art Mode matte, e.g. 'modern_black'")
    args = ap.parse_args()

    from samsungtvws import SamsungTVWS

    with tempfile.TemporaryDirectory() as tmp:
        shot = Path(tmp) / "pier.jpg"
        grab_frame(shot)

        tv = SamsungTVWS(host=args.host, port=8002,
                         token_file=str(Path(__file__).with_name(".tv_token")))
        art = tv.art()

        if not art.supported():
            print("This TV does not report Art Mode support.", file=sys.stderr)
            return 1

        new_id = art.upload(shot.read_bytes(), file_type="JPEG", matte=args.matte)
        art.select_image(new_id, show=True)
        print(f"uploaded {new_id}")

        # Remove the frame uploaded on the previous run.
        if STATE.exists():
            old = STATE.read_text().strip()
            if old and old != new_id:
                try:
                    art.delete(old)
                except Exception as exc:  # TV may have already dropped it
                    print(f"could not delete {old}: {exc}", file=sys.stderr)
        STATE.write_text(new_id)

    return 0


if __name__ == "__main__":
    sys.exit(main())
