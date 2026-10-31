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

SERVICE_ID="create-git-local-snapshots"
readonly SERVICE_NAME="Local Git Repository Snapshot Service"

SOURCE_DIR=""
DEST_DIR=""
SNAPSHOT_TMP_DIR=""

function usage() {
    cat <<EOF
Usage: $(basename "$0") --source <dir> --destination <dir>

Options:
  -s, --source <dir>      Source directory tree to snapshot (required)
  -d, --destination <dir> Snapshot root directory (required)
  -h, --help              Display this help message
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

    if [[ -z "$SOURCE_DIR" || -z "$DEST_DIR" ]]; then
        printf 'Error: --source and --destination are required.\n' >&2
        usage
        exit "$ERROR_INVALID_ARGS"
    fi
}

function cleanup_snapshot() {
    local exit_code=$?

    if [[ -n "$SNAPSHOT_TMP_DIR" ]]; then
        rm -rf -- "$SNAPSHOT_TMP_DIR" || true
    fi
    cleanup_and_report "$exit_code"
}

# -----------------------------------------------------------------------------
# BUSINESS LOGIC
# -----------------------------------------------------------------------------

function run_service() {
    local timestamp current_snapshot snapshot_dir
    local -a rsync_options=(-aH --delete --stats --human-readable)

    timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
    snapshot_dir="${DEST_DIR}/${timestamp}"
    current_snapshot="${DEST_DIR}/current"

    if [[ -e "$snapshot_dir" || -L "$snapshot_dir" ]]; then
        printf 'Error: Snapshot path already exists: %s\n' "$snapshot_dir" >&2
        return 1
    fi

    SNAPSHOT_TMP_DIR="$(mktemp -d "${DEST_DIR}/.in-progress-${timestamp}.XXXXXXXX")"

    if [[ -L "$current_snapshot" && -d "$current_snapshot" ]]; then
        rsync_options+=("--link-dest=${current_snapshot}")
    elif [[ -e "$current_snapshot" || -L "$current_snapshot" ]]; then
        printf 'Error: Current snapshot must be a symlink to a directory: %s\n' "$current_snapshot" >&2
        return 1
    fi

    printf 'Starting %s: %s (RUN_ID: %s)\n' "${SERVICE_NAME}" "$(date)" "$RUN_ID"

    run_and_log rsync "${rsync_options[@]}" \
        "${SOURCE_DIR}/" "${SNAPSHOT_TMP_DIR}/" || return 1

    mv -- "$SNAPSHOT_TMP_DIR" "$snapshot_dir"
    SNAPSHOT_TMP_DIR=""

    ln -sfn -- "$snapshot_dir" "$current_snapshot"
    METRICS_JSON="$(jq -n --arg snapshot "$timestamp" '{snapshot: $snapshot}')"

    printf '%s Finished: %s\n' "${SERVICE_NAME}" "$(date)"
}

function main() {
    parse_args "$@"
    init_telemetry "$SERVICE_ID"
    trap 'cleanup_snapshot' EXIT

    check_dependencies curl date jq ln mkdir mktemp mv readlink realpath rm rsync tee

    if [[ ! -d "$SOURCE_DIR" || ! -r "$SOURCE_DIR" ]]; then
        printf 'Error: Source directory "%s" does not exist or is not readable.\n' "$SOURCE_DIR" >&2
        exit "$ERROR_DIR_VALIDATION"
    fi

    mkdir -p -- "$DEST_DIR"
    ensure_writable_dir "$DEST_DIR" "Snapshot Root" || exit "$ERROR_DIR_VALIDATION"
    SOURCE_DIR="$(realpath "$SOURCE_DIR")"
    DEST_DIR="$(realpath "$DEST_DIR")"

    if [[ "$SOURCE_DIR" == "/" || "$DEST_DIR" == "$SOURCE_DIR" || "$DEST_DIR" == "$SOURCE_DIR/"* ]]; then
        printf 'Error: Snapshot root must not be the source directory or one of its descendants.\n' >&2
        exit "$ERROR_DIR_VALIDATION"
    fi

    start_telemetry
    run_service
}

main "$@"
