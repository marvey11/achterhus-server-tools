#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# IMPORTS
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LIB_DIR="$(realpath "${SCRIPT_DIR}/../../lib")"

# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=lib/utils.sh
source "${LIB_DIR}/utils.sh"
# shellcheck source=lib/telemetry.sh
source "${LIB_DIR}/telemetry.sh"

init_project_paths "$0"

# -----------------------------------------------------------------------------
# CONFIGURATION & OPTIONS
# -----------------------------------------------------------------------------

SERVICE_ID="backup-storage"
readonly SERVICE_NAME="Storage Drive Backup Service"

readonly RSYNC_ERR_VANISHED=24

SOURCE_DIR=""
DEST_DIR=""
DRY_RUN=false

function usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] -s <source_dir> -d <dest_dir>

Options:
  -s, --source <dir>      Source directory (required)
  -d, --destination <dir> Destination directory (required)
  -n, --dry-run           Perform a trial run with no changes made
  -h, --help                Display this help message
EOF
}

function parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source)      SOURCE_DIR="$2"; shift 2 ;;
            -d|--destination) DEST_DIR="$2"; shift 2 ;;
            -n|--dry-run)     DRY_RUN=true; shift ;;
            -h|--help)        usage; exit 0 ;;
            *)                usage; exit "$ERROR_INVALID_ARGS" ;;
        esac
    done

    if [[ -z "${SOURCE_DIR}" || -z "${DEST_DIR}" ]]; then
        printf 'Error: Both --source (-s) and --destination (-d) are required.\n' >&2
        usage
        exit "$ERROR_INVALID_ARGS"
    fi
}

# -----------------------------------------------------------------------------
# BUSINESS LOGIC
# -----------------------------------------------------------------------------

function run_service() {
    printf 'Starting %s: %s (RUN_ID: %s)\n' "${SERVICE_NAME}" "$(date)" "$RUN_ID"

    local rsync_opts=(-avhzx --delete --stats)
    if [[ "$DRY_RUN" == true ]]; then
        rsync_opts+=("--dry-run")
        printf '⚠️  Dry-run enabled. No changes will be made.\n'
    fi

    run_and_log rsync "${rsync_opts[@]}" \
        --exclude='lost+found/' \
        --exclude='temp/' \
        --exclude='.deleted/' \
        --exclude='.is_mounted' \
        "${SOURCE_DIR}/" "${DEST_DIR}/" || return 1

    local rsync_log
    rsync_log="$(tail -n 25 "$STATS_FILE" | tr -d ',')"

    local total_size xfer_size
    total_size="$(printf '%s\n' "${rsync_log}" | grep "total size is" | awk '{print $4}' || true)"
    xfer_size="$(printf '%s\n' "${rsync_log}" | grep "Total transferred file size" | awk '{print $5}' || true)"

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

    printf '%s Finished: %s\n' "${SERVICE_NAME}" "$(date)"
}

function main() {
    parse_args "$@"
    init_telemetry "$SERVICE_ID"

    check_dependencies curl rsync jq grep awk mktemp mountpoint

    ensure_is_mounted "${SOURCE_DIR}" "Data Storage" || exit "$ERROR_DIR_VALIDATION"
    ensure_is_mounted "${DEST_DIR}" "Backup Drive" || exit "$ERROR_DIR_VALIDATION"
    ensure_writable_dir "${DEST_DIR}" "Backup Drive" || exit "$ERROR_DIR_VALIDATION"

    allow_warning_exit_codes "$RSYNC_ERR_VANISHED"

    run_service
}

main "$@"
