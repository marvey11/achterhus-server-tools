#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="photo-processor"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT=$(realpath "${SCRIPT_DIR}/..")

# Discover Python (venv vs system)
PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"
if [ ! -f "$PYTHON_CMD" ]; then PYTHON_CMD="python3"; fi


function finish() {
    local exit_code=$?

    ${PYTHON_CMD} "${SCRIPT_DIR}/service_status.py" "${SERVICE_NAME}" "$exit_code"

    if [ "$exit_code" -ne 0 ]; then
        echo "❌ Photo processing failed with exit code $exit_code."
    fi
}


trap finish EXIT INT TERM

ENV_FILE="${PROJECT_ROOT}/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️ .env not found, attempting to generate..."
    ${PYTHON_CMD} "${SCRIPT_DIR}/generate_env.py" || {
        echo "❌ Failed to generate .env file."
        exit 1
    }
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

: "${PHOTO_INBOX:?Variable PHOTO_INBOX is not set or empty}"
: "${PHOTO_STORAGE:?Variable PHOTO_STORAGE is not set or empty}"

# Create folders
mkdir -p "$PHOTO_INBOX"
mkdir -p "$PHOTO_STORAGE"

echo "--- Photo Processing Started: $(date) ---"

# exiftool magic:
# -P: preserve file modification date
# -d "%Y": extract only the Year
# '-Directory<${DateTimeOriginal}': Set target dir based on that year
# -ext jpg: only process JPEGs

# NOTE: shellcheck complains about the ${DateTimeOriginal} expression in single
# quotes, but it is intentional to prevent variable expansion by the shell, as
# the directive is for exiftool --> disable the warning for that line.

# shellcheck disable=SC2016
exiftool -P -ext jpg -ext jpeg -r -d "${PHOTO_STORAGE}/%Y" \
    '-Directory<${DateTimeOriginal}' \
    "${PHOTO_INBOX}"

echo "--- Photo Processing Finished: $(date) ---"
