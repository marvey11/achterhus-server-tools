#!/bin/bash

set -euo pipefail

# Configuration
SERVICE_NAME="backup-drives"
METADATA="{}" # Default to empty JSON object

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT=$(realpath "${SCRIPT_DIR}/..")

# Discover Python (venv vs system)
PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"
if [ ! -f "$PYTHON_CMD" ]; then PYTHON_CMD="python3"; fi


function finish() {
    local exit_code=$?

    # Handle rsync's "Vanished source files" code
    # We report it as 0 to the dashboard because the backup is still valid
    if [ "$exit_code" -eq 24 ]; then
        echo "⚠️  Rsync reported vanished source files (code 24). Treating as Success."
        exit_code=0
    fi

    ${PYTHON_CMD} "${SCRIPT_DIR}/service_status.py" \
        "${SERVICE_NAME}" \
        "$exit_code" \
        --metadata "$METADATA"

    if [ "$exit_code" -ne 0 ]; then
        echo "❌ Storage backup failed with exit code $exit_code."
    fi
}


trap finish EXIT INT TERM

SOURCE="/mnt/storage/"
DEST="/mnt/backup/mirror/"

# Create destination if it doesn't exist
mkdir -p $DEST

if ! mountpoint -q "${SOURCE}" || ! mountpoint -q "/mnt/backup"; then
    echo "❌ One or more drives not mounted. Aborting."
    exit 1
fi

echo "--- Backup Started: $(date) ---"

# rsync command:
# -a (archive)
# -v (verbose)
# -h (human-readable)
# -z (compress during transfer)
# -x (don't cross filesystem boundaries)
# --delete (remove files at destination that are gone from source)
# --exclude (exclude specific directories, in this case 'lost+found', 'temp', and '.deleted/')
RSYNC_LOG=$(rsync -avhzx --delete \
    --exclude='lost+found' \
    --exclude='temp' \
    --exclude='.deleted/' \
    "${SOURCE}" "${DEST}" | tee /dev/stderr)

# Parsing rsync summary using grep/awk
# Example line: "total size is 1.23G  speedup is 1.00"
# Example line: "Number of files: 1,234 (reg: 1,100, dir: 134, ...)"
# Use '|| true' to prevent grep from crashing the script if stats are missing
TOTAL_SIZE=$(echo "${RSYNC_LOG}" | grep "total size is" | awk '{print $4}' || true)
XFER_SIZE=$(echo "${RSYNC_LOG}" | grep "Total transferred file size" | awk '{print $5 $6}' || true)

# Ensure we have fallback strings so the JSON isn't malformed
SAFE_TOTAL="${TOTAL_SIZE:-unknown}"
SAFE_XFER="${XFER_SIZE:-0 bytes (unchanged)}"

METADATA=$(cat <<EOF
{
"total_size": {
    "label": "Mirror Size",
    "value": "${SAFE_TOTAL}"
  },
  "transferred": {
    "label": "Data Sent",
    "value": "${SAFE_XFER}"
  }
}
EOF
)

echo "--- Backup Finished: $(date) ---"
