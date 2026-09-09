#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$HOME/Library/Application Support/classbar/schedule.json"
TMP="$(mktemp)"

echo "Fetching your registration from Banner..."
ego-browser nodejs < "$DIR/fetch-schedule.js" > "$TMP" 2>&1

python3 "$DIR/merge-schedule.py" "$TMP" "$OUT" "${1:-}"
rm -f "$TMP"
