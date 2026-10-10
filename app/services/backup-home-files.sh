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

SERVICE_ID="backup-home-files"
readonly SERVICE_NAME="Home Directory Files Backup Service"

SOURCE_DIR=""
DEST_DIR=""
FILES_FROM=""
DRY_RUN=false

function usage() {
    cat <<EOF
Usage: $(basename "$0") --source <dir> --destination <dir> --files-from <file>

Options:
  -s, --source <dir>          Source home directory (required)
  -d, --destination <dir>     Backup destination directory (required)
  -f, --files-from <file>     File containing paths relative to the source (required)
  -n, --dry-run               Show what would be transferred without copying files
  -h, --help                  Display this help message
EOF
}

function parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    printf 'Error: --source requires a directory.\n' >&2
                    usage
                    exit "$ERROR_INVALID_ARGS"
                fi
                SOURCE_DIR="$2"
                shift 2
                ;;
            -d|--destination)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    printf 'Error: --destination requires a directory.\n' >&2
                    usage
                    exit "$ERROR_INVALID_ARGS"
                fi
                DEST_DIR="$2"
                shift 2
                ;;
            -f|--files-from)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    printf 'Error: --files-from requires a file.\n' >&2
                    usage
                    exit "$ERROR_INVALID_ARGS"
                fi
                FILES_FROM="$2"
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
                usage
                exit "$ERROR_INVALID_ARGS"
                ;;
        esac
    done

    if [[ -z "$SOURCE_DIR" || -z "$DEST_DIR" || -z "$FILES_FROM" ]]; then
        printf 'Error: --source, --destination and --files-from are required.\n' >&2
        usage
        exit "$ERROR_INVALID_ARGS"
    fi
}

# -----------------------------------------------------------------------------
# BUSINESS LOGIC
# -----------------------------------------------------------------------------

function run_service() {
    local transferred_files

    printf 'Starting %s: %s (RUN_ID: %s)\n' "${SERVICE_NAME}" "$(date)" "$RUN_ID"

    local rsync_options=(-avz --stats --files-from="$FILES_FROM")
    if [[ "$DRY_RUN" == true ]]; then
        rsync_options+=(--dry-run)
        printf 'Dry-run enabled. No files will be copied.\n'
    fi

    run_and_log rsync "${rsync_options[@]}" \
        "${SOURCE_DIR}/" "${DEST_DIR}/" || return 1

    transferred_files="$(awk -F ': ' '/^Number of files transferred:/ {print $2}' "$STATS_FILE" | tail -n 1)"
    if [[ ! "$transferred_files" =~ ^[0-9]+$ ]]; then
        printf 'Error: Could not read the rsync transferred-file count.\n' >&2
        return 1
    fi

    METRICS_JSON="$(jq -n --argjson files_backed_up "$transferred_files" \
        '{files_backed_up: $files_backed_up}')"

    printf '%s Finished: %s\n' "${SERVICE_NAME}" "$(date)"
}

function main() {
    parse_args "$@"
    init_telemetry "$SERVICE_ID"

    check_dependencies awk curl jq mountpoint rsync tail tee

    ensure_is_mounted "$SOURCE_DIR" "Home Directory" || exit "$ERROR_DIR_VALIDATION"
    ensure_is_mounted "$DEST_DIR" "Backup Destination" || exit "$ERROR_DIR_VALIDATION"
    ensure_writable_dir "$DEST_DIR" "Backup Destination" || exit "$ERROR_DIR_VALIDATION"

    if [[ ! -f "$FILES_FROM" || ! -r "$FILES_FROM" ]]; then
        printf 'Error: Files-from list "%s" does not exist or is not readable.\n' "$FILES_FROM" >&2
        exit "$ERROR_DIR_VALIDATION"
    fi

    start_telemetry
    run_service
}

main "$@"
