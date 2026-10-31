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

SERVICE_ID="apply-git-local-retention"
readonly SERVICE_NAME="Local Git Repository Snapshot Retention Service"
readonly DAILY_RETENTION_SECONDS=$((28 * 24 * 60 * 60))

SNAPSHOT_DIR=""

function usage() {
    cat <<EOF
Usage: $(basename "$0") --snapshot-directory <dir>

Options:
  -d, --snapshot-directory <dir> Snapshot root directory (required)
  -h, --help                     Display this help message
EOF
}

function parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--snapshot-directory)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    printf 'Error: --snapshot-directory requires a directory.\n' >&2
                    usage
                    exit "$ERROR_INVALID_ARGS"
                fi
                SNAPSHOT_DIR="$2"
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

    if [[ -z "$SNAPSHOT_DIR" ]]; then
        printf 'Error: --snapshot-directory is required.\n' >&2
        usage
        exit "$ERROR_INVALID_ARGS"
    fi
}

function snapshot_timestamp_epoch() {
    local snapshot_name="$1"
    local timestamp="${snapshot_name:0:10} ${snapshot_name:11:2}:${snapshot_name:14:2}:${snapshot_name:17:2}"
    local parsed_timestamp

    if [[ ! "$snapshot_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
        return 1
    fi

    parsed_timestamp="$(date -d "$timestamp" +%s 2>/dev/null)" || return 1
    if [[ "$(date -d "@$parsed_timestamp" +%Y-%m-%d_%H-%M-%S 2>/dev/null)" != "$snapshot_name" ]]; then
        return 1
    fi

    printf '%s\n' "$parsed_timestamp"
}

function months_ago_epoch() {
    local month_offset="$1"
    local year month day hour minute second month_index target_year target_month max_day timestamp now_parts

    now_parts="$(date +'%Y %m %d %H %M %S')"
    read -r year month day hour minute second <<<"$now_parts"

    month_index=$((10#$year * 12 + 10#$month - 1 - month_offset))
    target_year=$((month_index / 12))
    target_month=$((month_index % 12 + 1))

    case "$target_month" in
        1|3|5|7|8|10|12) max_day=31 ;;
        4|6|9|11) max_day=30 ;;
        2)
            max_day=28
            if (( target_year % 400 == 0 || (target_year % 4 == 0 && target_year % 100 != 0) )); then
                max_day=29
            fi
            ;;
    esac

    if (( 10#$day > max_day )); then
        day="$max_day"
    fi

    timestamp="$(printf '%04d-%02d-%02d %02d:%02d:%02d' \
        "$target_year" "$target_month" "$((10#$day))" \
        "$((10#$hour))" "$((10#$minute))" "$((10#$second))")"
    date -d "$timestamp" +%s
}

# -----------------------------------------------------------------------------
# BUSINESS LOGIC
# -----------------------------------------------------------------------------

function run_service() {
    local now_epoch twelve_months_ago current_target snapshot_path snapshot_name snapshot_epoch month
    local deleted_count=0 kept_count=0
    local -a snapshots=()
    local -A snapshot_epochs=() monthly_keep=()

    now_epoch="$(date +%s)"
    twelve_months_ago="$(months_ago_epoch 12)"
    current_target="$(readlink -f -- "${SNAPSHOT_DIR}/current" 2>/dev/null || true)"

    for snapshot_path in "${SNAPSHOT_DIR}"/*; do
        [[ -d "$snapshot_path" && ! -L "$snapshot_path" ]] || continue

        snapshot_name="${snapshot_path##*/}"
        snapshot_epoch="$(snapshot_timestamp_epoch "$snapshot_name")" || continue
        snapshots+=("$snapshot_name")
        snapshot_epochs["$snapshot_name"]="$snapshot_epoch"

        if (( snapshot_epoch > now_epoch - DAILY_RETENTION_SECONDS )); then
            continue
        fi

        if (( snapshot_epoch > twelve_months_ago )); then
            month="${snapshot_name:0:7}"
            monthly_keep["$month"]="$snapshot_name"
        fi
    done

    for snapshot_name in "${snapshots[@]}"; do
        snapshot_path="${SNAPSHOT_DIR}/${snapshot_name}"
        snapshot_epoch="${snapshot_epochs[$snapshot_name]}"

        if [[ "$snapshot_path" -ef "$current_target" ]] 2>/dev/null; then
            ((kept_count += 1))
            continue
        fi

        if (( snapshot_epoch > now_epoch - DAILY_RETENTION_SECONDS )); then
            ((kept_count += 1))
            continue
        fi

        if (( snapshot_epoch > twelve_months_ago )) &&
            [[ "${monthly_keep[${snapshot_name:0:7}]:-}" == "$snapshot_name" ]]; then
            ((kept_count += 1))
            continue
        fi

        rm -rf -- "$snapshot_path"
        ((deleted_count += 1))
    done

    METRICS_JSON="$(jq -n \
        --argjson snapshots_kept "$kept_count" \
        --argjson snapshots_deleted "$deleted_count" \
        '{snapshots_kept: $snapshots_kept, snapshots_deleted: $snapshots_deleted}')"

    printf '%s Finished: %s (kept %d, deleted %d)\n' \
        "${SERVICE_NAME}" "$(date)" "$kept_count" "$deleted_count"
}

function main() {
    parse_args "$@"
    init_telemetry "$SERVICE_ID"

    check_dependencies curl date jq readlink rm

    if [[ ! -d "$SNAPSHOT_DIR" ]]; then
        printf 'Error: Snapshot directory "%s" does not exist.\n' "$SNAPSHOT_DIR" >&2
        exit "$ERROR_DIR_VALIDATION"
    fi
    ensure_writable_dir "$SNAPSHOT_DIR" "Snapshot Root" || exit "$ERROR_DIR_VALIDATION"
    SNAPSHOT_DIR="$(cd -- "$SNAPSHOT_DIR" && pwd -P)"

    start_telemetry
    run_service
}

main "$@"
