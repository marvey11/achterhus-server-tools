#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# SCRIPT CONFIGURATION
# -----------------------------------------------------------------------------

readonly SERVICE_ID="backup-storage"
# readonly SERVICE_NAME="Back up Storage Drive"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
readonly SCRIPT_DIR

PROJECT_ROOT=$(realpath "${SCRIPT_DIR}/../..")
readonly PROJECT_ROOT

LIB_DIR=${PROJECT_ROOT}/lib
readonly LIB_DIR

readonly TELEMETRY_URL="${TELEMETRY_URL:-http://telemetry-api:8000}"

# Error codes
readonly ERROR_INVALID_ARGS=2
readonly ERROR_DIR_VALIDATION=254

# Default values
SOURCE_DIR=""
DEST_DIR=""
DRY_RUN=false

# -----------------------------------------------------------------------------
# IMPORTS
# -----------------------------------------------------------------------------

# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# shellcheck source=lib/utils.sh
source "${LIB_DIR}/utils.sh"

# shellcheck source=lib/telemetry.sh
source "${LIB_DIR}/telemetry.sh"

# -----------------------------------------------------------------------------
# USAGE & ARGUMENT PARSING
# -----------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] -s <source_dir> -d <dest_dir>

Options:
  -s, --source <dir>      Source directory (required)
  -d, --destination <dir> Destination directory (required)
  -n, --dry-run           Perform a trial run with no changes made
  -h, --help              Display this help message
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source)
                SOURCE_DIR="$2"
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

    if [[ -z "${SOURCE_DIR}" || -z "${DEST_DIR}" ]]; then
        printf 'Error: Both --source (-s) and --destination (-d) are required.\n' >&2
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

ERROR_LOG="$(mktemp)"
STATS_FILE="$(mktemp)"
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
# SANITY CHECKS
# -----------------------------------------------------------------------------

run_pre_checks() {
    # Source must be mounted
    ensure_is_mounted "${SOURCE_DIR}" "Data Storage" || return 1

    # Destination must be mounted and writable
    ensure_is_mounted "${DEST_DIR}" "Backup Drive" || return 1
    ensure_writable_dir "${DEST_DIR}" "Backup Drive" || return 1

    return 0
}

# -----------------------------------------------------------------------------
# MAIN BUSINESS LOGIC
# -----------------------------------------------------------------------------

run_service() {
    printf 'Starting Backup Service: %s (RUN_ID: %s)\n' "$(date)" "$RUN_ID"

    # Configure `rsync` options
    local rsync_opts=(-avhzx --delete --stats)
    if [[ "$DRY_RUN" == true ]]; then
        rsync_opts+=("--dry-run")
        printf '⚠️  Dry-run enabled. No changes will be made.\n'
    fi

    # Execute `rsync` command and capture stdout/stderr output
    if ! rsync "${rsync_opts[@]}" \
        --exclude='lost+found/' \
        --exclude='temp/' \
        --exclude='.deleted/' \
        --exclude='.is_mounted' \
        "${SOURCE_DIR}/" "${DEST_DIR}/" 2>&1 | tee "$STATS_FILE" "$ERROR_LOG"; then
        printf 'Error: rsync operation failed.\n' >&2
        return 1
    fi

    # Extract the last 25 lines from the temp file for the metadata
    local rsync_log
    rsync_log="$(tail -n 25 "$STATS_FILE" | tr -d ',')"

    # Parsing `rsync` summary
    local total_size xfer_size
    total_size="$(printf '\%s\n' "${rsync_log}" | grep "total size is" | awk '{print $4}' || true)"
    xfer_size="$(printf '\%s\n' "${rsync_log}" | grep "Total transferred file size" | awk '{print $5}' || true)"

    # Ensure fallback strings so the JSON isn't malformed
    local safe_total="${total_size:-unknown}"
    local safe_xfer

    if [[ -z "${xfer_size}" || "${xfer_size}" == "0" ]]; then
        safe_xfer="None (unchanged)"
    elif [[ "${xfer_size}" =~ ^[0-9]+$ ]]; then
        safe_xfer="${xfer_size} bytes"
    else
        safe_xfer="${xfer_size}"
    fi

    METRICS_JSON=$(jq -n \
        --arg mirror_size "${safe_total}" \
        --arg transfer_size "${safe_xfer}" \
        '{
            mirror_size: $mirror_size,
            data_sent: $transfer_size
        }'
    )

    printf 'Backup Service Finished: %s\n' "$(date)"
}

main() {
    parse_args "$@"
    run_pre_checks || exit $ERROR_DIR_VALIDATION
    run_service
}

main "$@"
