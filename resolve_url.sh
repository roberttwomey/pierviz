#!/usr/bin/env bash
# Resolve a fresh, signed HLS URL for the Scripps Pier underwater cam.
# The URL from HDOnTap carries a token that expires in ~12h, so it must be
# re-fetched rather than hardcoded.
set -euo pipefail

STREAM="${STREAM:-scripps_pier-underwater-CUST}"
EMBED="https://portal.hdontap.com/s/embed/?stream=${STREAM}&ratio=16:9&fluid=true"
REF_B64=$(printf '%s' "$EMBED" | base64 | tr -d '\n')

curl -fsS --max-time 20 "https://portal.hdontap.com/backend/embed/${STREAM}?r=${REF_B64}" \
  | base64 -d \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["streamSrc"])'
