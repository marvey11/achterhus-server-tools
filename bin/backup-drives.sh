#!/bin/bash

set -euo pipefail


# -----------------------------------------------------------------------------
# SCRIPT CONFIGURATION
# -----------------------------------------------------------------------------

SERVICE_NAME="backup-drives"
METADATA="{}" # Default to empty JSON object

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT=$(realpath "${SCRIPT_DIR}/..")

# Discover Python (venv vs system)
PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"
if [ ! -f "$PYTHON_CMD" ]; then PYTHON_CMD="python3"; fi

# Error codes
ERROR_DIR_VALIDATION=254


# -----------------------------------------------------------------------------
# EXIT STRATEGY
# -----------------------------------------------------------------------------

function finish() {
    local exit_code=$?

    # Handle rsync's "Vanished source files" code
    # We report it as 0 to the dashboard because the backup is still valid
    if [ "$exit_code" -eq 24 ]; then
        echo "⚠️  Rsync reported vanished source files (code 24). Treating as Success."
        exit_code=0
    fi

    if [ "$exit_code" -eq $ERROR_DIR_VALIDATION ]; then
        echo "❌ Critical: Directory validation failed (Mount/Permissions)."
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

: "${STORAGE_DIR:?Variable STORAGE_DIR is not set or empty}"
: "${BACKUP_DIR:?Variable BACKUP_DIR is not set or empty}"

DRY_RUN=false

while getopts "s:d:n" opt; do
  case $opt in
    s) STORAGE_DIR="$OPTARG";;
    d) BACKUP_DIR="$OPTARG";;
    n) DRY_RUN=true;; # 'n' is common for 'no-op' (dry-run)
    *) echo "Usage: $0 [-s source] [-d dest] [-n (dry-run)]" >&2
       exit 1 ;;
  esac
done


# -----------------------------------------------------------------------------
# SANITY CHECKS
# -----------------------------------------------------------------------------

# shellcheck source=../lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh"

function check_directories() {
    # Source must be mounted
    ensure_is_mounted "${STORAGE_DIR}" "Data Storage" || return 1

    # Destination must be mounted and writable
    ensure_is_mounted "${BACKUP_DIR}" "Backup Drive" || return 1
    ensure_writable_dir "${BACKUP_DIR}" "Backup Drive" || return 1

    return 0
}

check_directories || exit $ERROR_DIR_VALIDATION

# -----------------------------------------------------------------------------
# ASSEMBLE AND RUN THE RSYNC COMMAND
# -----------------------------------------------------------------------------

echo "--- Backup Started: $(date) ---"

# Temporary file for stats
STATS_FILE=$(mktemp)

# Add --dry-run to rsync args if the script is in dry-run mode
RSYNC_OPTS=(-avhzx --delete --stats)
if [ "$DRY_RUN" == true ]; then
    RSYNC_OPTS+=("--dry-run")
    echo "⚠️  Dry-run enabled. No changes will be made."
fi

# rsync command:
# -a (archive)
# -v (verbose)
# -h (human-readable)
# -z (compress during transfer)
# -x (don't cross filesystem boundaries)
# --delete (remove files at destination that are gone from source)
# --exclude (exclude specific directories, in this case 'lost+found', 'temp', and '.deleted')
rsync "${RSYNC_OPTS[@]}" \
    --exclude='lost+found/' \
    --exclude='temp/' \
    --exclude='.deleted/' \
    "${STORAGE_DIR}/" "${BACKUP_DIR}/" | tee "$STATS_FILE"

# Extract the last 25 lines from the temp file for the metadata
RSYNC_LOG=$(tail -n 25 "$STATS_FILE")
rm "$STATS_FILE"


# -----------------------------------------------------------------------------
# EXTRACT METADATA
# -----------------------------------------------------------------------------

# Parsing rsync summary using grep/awk
# Example line: "total size is 1.23G  speedup is 1.00"
# Example line: "Number of files: 1,234 (reg: 1,100, dir: 134, ...)"
# Use '|| true' to prevent grep from crashing the script if stats are missing
TOTAL_SIZE=$(echo "${RSYNC_LOG}" | grep "total size is" | awk '{print $4}' || true)
XFER_SIZE=$(echo "${RSYNC_LOG}" | grep "Total transferred file size" | awk '{print $5}' || true)

# Ensure we have fallback strings so the JSON isn't malformed
SAFE_TOTAL="${TOTAL_SIZE:-unknown}"

if [[ -z "${XFER_SIZE}" || "${XFER_SIZE}" == "0" ]]; then
    # 0, empty, or unset all at once
    SAFE_XFER="None (unchanged)"
elif [[ "${XFER_SIZE}" =~ ^[0-9]+$ ]]; then
    # purely numeric (and not 0, since that's handled above)
    SAFE_XFER="${XFER_SIZE} bytes"
else
    # everything else (e.g., "7.21M", "10G")
    SAFE_XFER="${XFER_SIZE}"
fi

METADATA=$(cat <<EOF
{
  "total_size": { "label": "Mirror Size", "value": "${SAFE_TOTAL}" },
  "transferred": { "label": "Data Sent", "value": "${SAFE_XFER}" },
  "dry_run": { "label": "Dry-Run Mode", "value": "${DRY_RUN}" }
}
EOF
)

echo "--- Backup Finished: $(date) ---"
