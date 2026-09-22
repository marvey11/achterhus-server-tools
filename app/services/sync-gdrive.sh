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
# SCRIPT CONFIGURATION
# -----------------------------------------------------------------------------

readonly SERVICE_ID="sync-gdrive"
# readonly SERVICE_NAME="Sync Google Drive"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
readonly SCRIPT_DIR

PROJECT_ROOT=$(realpath "${SCRIPT_DIR}/../..")
readonly PROJECT_ROOT

LIB_DIR=${PROJECT_ROOT}/lib
readonly LIB_DIR

readonly TELEMETRY_URL="${TELEMETRY_URL:-http://telemetry-api:8000}"

# Error codes
readonly ERROR_INVALID_ARGS=2

# Default values
GDRIVE_SOURCE=""
DEST_DIR=""
DRY_RUN=false

# -----------------------------------------------------------------------------
# IMPORTS
# -----------------------------------------------------------------------------

# shellcheck source=lib/telemetry.sh
source "${LIB_DIR}/telemetry.sh"

# shellcheck source=lib/utils.sh
source "${LIB_DIR}/utils.sh"

# -----------------------------------------------------------------------------
# USAGE & ARGUMENT PARSING
# -----------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] -g <gdrive_source> -d <dest_dir>

Options:
  -g, --gdrive-source <dir> Source directory (required)
  -d, --destination <dir>   Destination directory (required)
  -n, --dry-run             Perform a trial run with no changes made
  -h, --help                Display this help message
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -g|--gdrive-source)
                GDRIVE_SOURCE="$2"
                shift 2
                ;;
            -d|--destination)
                DEST_DIR="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'Error: Unknown argument %s\n' "$1" >&2
                usage
                exit $ERROR_INVALID_ARGS
                ;;
        esac
    done

    if [[ -z "${GDRIVE_SOURCE}" || -z "${DEST_DIR}" ]]; then
        printf 'Error: Both --gdrive-source (-g) and --destination (-d) are required.\n' >&2
        usage
        exit $ERROR_INVALID_ARGS
    fi
}

# -----------------------------------------------------------------------------
# GLOBAL STATE & TRAP SETUP
# -----------------------------------------------------------------------------

RUN_ID="$(generate_uuid)"
STARTED_AT="$(get_iso8601)"
START_TIME="$(date +%s)"

# Temporary files
STATS_FILE=$(mktemp)
ERROR_LOG=$(mktemp)
METRICS_JSON="{}"

cleanup_and_report() {
    local exit_code=$?
    trap - EXIT

    local ended_at
    ended_at="$(get_iso8601)"

    local end_time
    end_time="$(date +%s)"

    local duration_seconds
    duration_seconds=$(( end_time - START_TIME ))

    local status="SUCCESS"
    local error_msg=""
    local logs_summary=""

    if [[ "$exit_code" -ne 0 ]]; then
        status="FAILED"
        if [[ -s "$ERROR_LOG" ]]; then
            logs_summary="$(tail -n 10 "$ERROR_LOG" | tr '\n' ' ' | sed 's/"/\\"/g')"
            error_msg="Script terminated with exit code $exit_code. stderr summary: $logs_summary"
        else
            error_msg="Script terminated with exit code $exit_code."
        fi
    fi

    printf '\n[Telemetry] Run status: %s (Duration: %ss)\n' "$status" "$duration_seconds"
    send_telemetry \
        "${TELEMETRY_URL}/api/v1/runs" \
        "$SERVICE_ID" \
        "$RUN_ID" \
        "$status" \
        "$STARTED_AT" \
        "$ended_at" \
        "$duration_seconds" \
        "$METRICS_JSON" \
        "$error_msg" \
        "$logs_summary" || printf 'Warning: Failed to send telemetry.\n' >&2

    rm -f "$ERROR_LOG" "$STATS_FILE"
}

trap cleanup_and_report EXIT

# -----------------------------------------------------------------------------
# MAIN BUSINESS LOGIC
# -----------------------------------------------------------------------------

run_service() {
    printf 'Starting Google Drive Sync Service: %s (RUN_ID: %s)\n' "$(date)" "$RUN_ID"

    # Configure `rclone` options
    local rclone_opts=(--checksum --drive-use-trash=false --log-level=INFO)
    if [[ "$DRY_RUN" == true ]]; then
        rclone_opts+=("--dry-run")
        printf '⚠️  Dry-run enabled. No changes will be made.\n'
    fi

    # Execute `rclone` command and capture stdout/stderr output
    if ! rclone move "$GDRIVE_SOURCE" "$DEST_DIR" "${rclone_opts[@]}" 2>&1 | tee "$STATS_FILE" "$ERROR_LOG"; then
        printf 'Error: rclone operation failed.\n' >&2
        return 1
    fi

    # Parsing `rclone` summary
    local raw_xfer xfer_value xfer_unit
    raw_xfer=$(grep "Transferred:" "${STATS_FILE}" | grep -iE "[0-9] [ZEPTGMK]?i?B /" | head -n 1 || true)
    xfer_value=$(echo "$raw_xfer" | awk '{print $2}')
    xfer_unit=$(echo "$raw_xfer" | awk '{print $3}')

    local file_count
    if [[ "$DRY_RUN" == true ]]; then
        file_count=$(grep "Transferred:" "${STATS_FILE}" | grep -vE "[ZEPTGMK]i?B" | awk '{print $2}' || echo "0")
    else
        file_count=$(grep "Deleted:" "${STATS_FILE}" | awk '{print $2}' || echo "0")
    fi

    # Default values if extraction fails (e.g. 0 files moved)
    xfer_value=${xfer_value:-"0"}
    xfer_unit=${xfer_unit:-"Bytes"}
    file_count=${file_count:-"0"}

    # Ensure numeric value for JSON parsing
    if ! [[ "$file_count" =~ ^[0-9]+$ ]]; then
        file_count=0
    fi

    METRICS_JSON=$(jq -n \
        --argjson file_count "$file_count" \
        --arg data_sent "$xfer_value$xfer_unit" \
        '{
            file_count: $file_count,
            transfer_size: $data_sent
        }'
    )

    printf 'Google Drive Sync Service Finished: %s\n' "$(date)"
}

main() {
    parse_args "$@"
    run_service
}

main "$@"
