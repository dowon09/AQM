#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONFIG_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$CONFIG_FILE" ]; then
    printf 'Missing %s. Copy .env.example to .env and set the API URL and device key.\n' "$CONFIG_FILE" >&2
    exit 1
fi

set -a
. "$CONFIG_FILE"
set +a

: "${API_URL:?Set API_URL in aqm-raspberry/.env}"
: "${DEVICE_API_KEY:?Set DEVICE_API_KEY in aqm-raspberry/.env}"

VENV="$SCRIPT_DIR/venv"

if [ ! -x "$VENV/bin/python" ]; then
    printf 'Creating isolated Python environment...\n'
    python3 -m venv "$VENV"
fi

printf 'Checking Python dependencies...\n'
"$VENV/bin/python" -m pip install -r "$SCRIPT_DIR/requirements.txt"

exec "$VENV/bin/python" "$SCRIPT_DIR/run.py"