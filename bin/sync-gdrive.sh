#!/usr/bin/env bash

set -euo pipefail


# -----------------------------------------------------------------------------
# IMPORTANT:
#
# This script relies on `rclone` which needs to be installed on the host
# system.
#
# For more information on configuring remotes in `rclone` and general usage,
# please see their homepage: https://rclone.org/
#
# For more information on using `rclone` with Google Drive, see the specific
# Google Drive page: https://rclone.org/drive/
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# SCRIPT CONFIGURATION
# -----------------------------------------------------------------------------

SERVICE_NAME="sync-google-drive"
METADATA="{}" # Default to empty JSON object

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT=$(realpath "${SCRIPT_DIR}/..")

# Discover Python (venv vs system)
PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"
if [ ! -f "$PYTHON_CMD" ]; then PYTHON_CMD="python3"; fi


# -----------------------------------------------------------------------------
# EXIT STRATEGY
# -----------------------------------------------------------------------------

function finish() {
    local exit_code=$?

    ${PYTHON_CMD} "${SCRIPT_DIR}/service_status.py" \
        "${SERVICE_NAME}" \
        "$exit_code" \
        --metadata "$METADATA"

    if [ "$exit_code" -ne 0 ]; then
        echo "❌ Google Drive Sync failed with exit code $exit_code."
    fi
}

trap finish EXIT INT TERM


# -----------------------------------------------------------------------------
# READ THE CONFIGURATION AND CHECK SCRIPT OPTIONS
# -----------------------------------------------------------------------------

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

: "${GDRIVE_SOURCE:?Variable GDRIVE_SOURCE is not set or empty}"
: "${DOCUMENT_INBOX:?Variable DOCUMENT_INBOX is not set or empty}"

DRY_RUN=false

while getopts "n" opt; do
  case $opt in
    n) DRY_RUN=true;;
    *) echo "Usage: $0 [-n (dry-run)]" >&2; exit 1 ;;
  esac
done


# -----------------------------------------------------------------------------
# ASSEMBLE AND RUN THE RCLONE COMMAND
# -----------------------------------------------------------------------------

echo "--- Google Drive Sync Started: $(date) ---"

# Temporary file for stats
RCLONE_STATS=$(mktemp)

# Add --dry-run to rsync args if the script is in dry-run mode
RCLONE_OPTS=(--checksum --drive-use-trash=false --log-level=INFO)
if [ "$DRY_RUN" == true ]; then
    RCLONE_OPTS+=("--dry-run")
    echo "⚠️  Dry-run enabled. No changes will be made."
fi

rclone move "$GDRIVE_SOURCE" "$DOCUMENT_INBOX" "${RCLONE_OPTS[@]}" 2>&1 | tee "${RCLONE_STATS}"


# -----------------------------------------------------------------------------
# EXTRACT METADATA
# -----------------------------------------------------------------------------

RAW_XFER=$(grep "Transferred:" "${RCLONE_STATS}" | grep -iE "[0-9] [ZEPTGMK]?i?B /" | head -n 1)
XFER_VALUE=$(echo "$RAW_XFER" | awk '{print $2}')
XFER_UNIT=$(echo "$RAW_XFER" | awk '{print $3}')

if [ "$DRY_RUN" == true ]; then
    # In dry-run, rclone doesn't 'Delete', so we look at the Transfers count line
    # This is the line that looks like "Transferred: 1 / 1"
    FILE_COUNT=$(grep "Transferred:" "${RCLONE_STATS}" | grep -vE "[ZEPTGMK]i?B" | awk '{print $2}' || echo "0")
else
    # In a real run, we use the Deleted line: "Deleted: 1 (files)..."
    FILE_COUNT=$(grep "Deleted:" "${RCLONE_STATS}" | awk '{print $2}' || echo "0")
fi

# Default values if extraction fails (e.g. 0 files moved)
XFER_VALUE=${XFER_VALUE:-"0"}
XFER_UNIT=${XFER_UNIT:-"Bytes"}
FILE_COUNT=${FILE_COUNT:-"0"}

rm -f "${RCLONE_STATS}"

METADATA=$(cat <<EOF
{
  "file_count": { "label": "Files Moved", "value": "${FILE_COUNT}", "unit": " files" },
  "transferred": { "label": "Data Sent", "value": "${XFER_VALUE}", "unit": " ${XFER_UNIT}" },
  "dry_run": { "label": "Dry-Run Mode", "value": "${DRY_RUN}" }
}
EOF
)

echo "--- Google Drive Sync Finished: $(date) ---"
