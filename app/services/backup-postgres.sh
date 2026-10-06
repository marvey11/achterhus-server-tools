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

SERVICE_ID="backup-postgres"
readonly SERVICE_NAME="PostgreSQL Database Backup Service"

DEST_DIR=""
BACKUP_TMP_DIR=""

function usage() {
    cat <<EOF
Usage: $(basename "$0") --destination <dir>

Options:
  -d, --destination <dir> Destination directory (required)
  -h, --help              Display this help message
EOF
}

function parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
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

    if [[ -z "$DEST_DIR" ]]; then
        printf 'Error: --destination is required.\n' >&2
        usage
        exit "$ERROR_INVALID_ARGS"
    fi
}

function cleanup_backup_tmp_dir() {
    local exit_code=$?

    if [[ -n "$BACKUP_TMP_DIR" ]]; then
        rm -rf -- "$BACKUP_TMP_DIR" || true
    fi
    cleanup_and_report "$exit_code"
}

# -----------------------------------------------------------------------------
# BUSINESS LOGIC
# -----------------------------------------------------------------------------

function run_service() {
    local database_host="${DATABASE_HOST:-postgres}"
    local database_port="${DATABASE_PORT:-5432}"
    local timestamp database_file globals_file
    local database_size globals_size total_size

    printf 'Starting %s: %s (RUN_ID: %s)\n' "${SERVICE_NAME}" "$(date)" "$RUN_ID"

    if ! pg_isready --host "$database_host" --port "$database_port" \
        --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"; then
        printf 'Error: PostgreSQL is not ready at %s:%s.\n' "$database_host" "$database_port" >&2
        return 1
    fi

    timestamp="$(date +%Y%m%d_%H%M%S)"
    database_file="achterhus_db_${timestamp}.sql.gz"
    globals_file="achterhus_db_globals_${timestamp}.sql.gz"
    BACKUP_TMP_DIR="$(mktemp -d "${DEST_DIR}/.backup-postgres.XXXXXXXX")"

    if ! pg_dump --host "$database_host" --port "$database_port" \
        --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
        2>>"$ERROR_LOG" | gzip -c >"${BACKUP_TMP_DIR}/${database_file}"; then
        printf 'Error: Database dump failed.\n' >&2
        return 1
    fi

    if ! pg_dumpall --host "$database_host" --port "$database_port" \
        --username "$POSTGRES_USER" --database "$POSTGRES_DB" --globals-only \
        2>>"$ERROR_LOG" | gzip -c >"${BACKUP_TMP_DIR}/${globals_file}"; then
        printf 'Error: PostgreSQL globals dump failed.\n' >&2
        return 1
    fi

    database_size="$(wc -c <"${BACKUP_TMP_DIR}/${database_file}")"
    globals_size="$(wc -c <"${BACKUP_TMP_DIR}/${globals_file}")"
    total_size=$((database_size + globals_size))

    mv -- "${BACKUP_TMP_DIR}/${database_file}" "${DEST_DIR}/${database_file}"
    mv -- "${BACKUP_TMP_DIR}/${globals_file}" "${DEST_DIR}/${globals_file}"

    METRICS_JSON="$(jq -n \
        --argjson database_backup_size_bytes "$database_size" \
        --argjson globals_backup_size_bytes "$globals_size" \
        --argjson total_backup_size_bytes "$total_size" \
        '{
            database_backup_size_bytes: $database_backup_size_bytes,
            globals_backup_size_bytes: $globals_backup_size_bytes,
            total_backup_size_bytes: $total_backup_size_bytes
        }'
    )"

    printf '%s Finished: %s\n' "${SERVICE_NAME}" "$(date)"
}

function main() {
    parse_args "$@"
    init_telemetry "$SERVICE_ID"
    trap 'cleanup_backup_tmp_dir' EXIT

    check_dependencies curl gzip jq mktemp mv pg_dump pg_dumpall pg_isready rm wc

    : "${POSTGRES_USER:?POSTGRES_USER must be set}"
    : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set}"
    : "${POSTGRES_DB:?POSTGRES_DB must be set}"
    export PGPASSWORD="$POSTGRES_PASSWORD"

    ensure_writable_dir "$DEST_DIR" "PostgreSQL Backup Destination" || exit "$ERROR_DIR_VALIDATION"

    start_telemetry
    run_service
}

main "$@"
