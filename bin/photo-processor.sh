#!/usr/bin/env bash

# Use -e to exit immediately if a command exits with a non-zero status
# Use -u to treat unset variables as an error
set -eu

SERVICE="photo-processor"
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

function finish() {
    local exit_code=$?

    python3 "${SCRIPT_DIR}/service_status.py" "$SERVICE" "$exit_code"

    if [ "$exit_code" -ne 0 ]; then
        echo "❌ Photo processing failed with exit code $exit_code."
    else
        echo "✅ Photo processing completed successfully."
    fi
}

trap finish EXIT INT TERM

ENV_FILE="${SCRIPT_DIR}/../.env"

# Ensure generate_env.py is called correctly
if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️ .env not found, attempting to generate..."
    python3 "${SCRIPT_DIR}/generate_env.py" || {
        echo "❌ Failed to generate .env file."
        exit 1
    }
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

# Validation: ensure critical variables were actually loaded
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
