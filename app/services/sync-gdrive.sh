#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# IMPORTANT:
#
# This script relies on `rclone` which needs to be installed on the host
# system / container environment.
#
# For more information on configuring remotes in `rclone` and general usage,
# please see their homepage: https://rclone.org/
#
# For more information on using `rclone` with Google Drive, see the specific
# Google Drive page: https://rclone.org/drive/
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# IMPORTS & INITIALISATION
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LIB_DIR="$(realpath "${SCRIPT_DIR}/../../lib")"

# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# shellcheck source=lib/telemetry.sh
source "${LIB_DIR}/telemetry.sh"

# shellcheck source=lib/utils.sh
source "${LIB_DIR}/utils.sh"

init_project_paths "$0"

# -----------------------------------------------------------------------------
# CONFIGURATION & OPTIONS
# -----------------------------------------------------------------------------

SERVICE_ID="sync-gdrive"
readonly SERVICE_NAME="Google Drive Sync Service"

RCLONE_CONFIG_DIR=${HOME}/.config/rclone
readonly RCLONE_CONFIG_DIR

GDRIVE_SOURCE=""
DEST_DIR=""
DRY_RUN=false

function usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] -g <gdrive_source> -d <dest_dir>

Options:
  -g, --gdrive-source <dir> Source directory (required)
  -d, --destination <dir>   Destination directory (required)
  -n, --dry-run             Perform a trial run with no changes made
  -h, --help                Display this help message
EOF
}

function parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -g|--gdrive-source) GDRIVE_SOURCE="$2"; shift 2 ;;
            -d|--destination)   DEST_DIR="$2"; shift 2 ;;
            -n|--dry-run)       DRY_RUN=true; shift ;;
            -h|--help)          usage; exit 0 ;;
            *)                  usage; exit "$ERROR_INVALID_ARGS" ;;
        esac
    done

    if [[ -z "${GDRIVE_SOURCE}" || -z "${DEST_DIR}" ]]; then
        printf 'Error: Both --gdrive-source (-g) and --destination (-d) are required.\n' >&2
        usage
        exit "$ERROR_INVALID_ARGS"
    fi
}

# -----------------------------------------------------------------------------
# BUSINESS LOGIC
# -----------------------------------------------------------------------------

function run_service() {
    printf 'Starting %s: %s (RUN_ID: %s)\n' "${SERVICE_NAME}" "$(date)" "$RUN_ID"

    local rclone_opts=(--checksum --drive-use-trash=false --log-level=INFO --stats-one-line)
    if [[ "$DRY_RUN" == true ]]; then
        rclone_opts+=("--dry-run")
        printf '⚠️  Dry-run enabled. No changes will be made.\n'
    fi

    run_and_log rclone move "$GDRIVE_SOURCE" "$DEST_DIR" "${rclone_opts[@]}" || return 1

    local raw_xfer xfer_value xfer_unit file_count
    raw_xfer=$(grep "Transferred:" "${STATS_FILE}" | grep -iE "[0-9] [ZEPTGMK]?i?B /" | head -n 1 || true)
    xfer_value=$(echo "$raw_xfer" | awk '{print $2}')
    xfer_unit=$(echo "$raw_xfer" | awk '{print $3}')

    if [[ "$DRY_RUN" == true ]]; then
        file_count=$(grep "Transferred:" "${STATS_FILE}" | grep -vE "[ZEPTGMK]i?B" | awk '{print $2}' || echo "0")
    else
        file_count=$(grep "Deleted:" "${STATS_FILE}" | awk '{print $2}' || echo "0")
    fi

    xfer_value=${xfer_value:-"0"}
    xfer_unit=${xfer_unit:-"Bytes"}
    file_count=${file_count:-"0"}

    [[ "$file_count" =~ ^[0-9]+$ ]] || file_count=0

    echo "FILE COUNT: ${file_count}"
    echo "DATA SENT: $xfer_value $xfer_unit"

    METRICS_JSON=$(jq -n \
        --argjson file_count "$file_count" \
        --arg data_sent "$xfer_value $xfer_unit" \
        '{
            file_count: $file_count,
            transfer_size: $data_sent
        }'
    )

    printf '%s Finished: %s\n' "${SERVICE_NAME}" "$(date)"
}

function main() {
    parse_args "$@"
    init_telemetry "$SERVICE_ID"

    check_dependencies curl rclone jq grep awk mktemp mountpoint

    ensure_writable_dir "${RCLONE_CONFIG_DIR}" "rconf config dir" || exit "$ERROR_DIR_VALIDATION"
    ensure_writable_dir "${DEST_DIR}" "Google Drive Sync Destination" || exit "$ERROR_DIR_VALIDATION"

    run_service
}

main "$@"
