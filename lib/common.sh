# shellcheck shell=bash

# Standard exit codes across all services
readonly ERROR_INVALID_ARGS=2
readonly ERROR_MISSING_DEPENDENCY=3
readonly ERROR_DIR_VALIDATION=4

# Resolve project root and lib directories relative to the calling script
function init_project_paths() {
    local caller_script="${1:?Script path required}"

    SCRIPT_DIR="$(dirname "$(readlink -f "$caller_script")")"
    PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../..")"
    LIB_DIR="${PROJECT_ROOT}/lib"

    export SCRIPT_DIR PROJECT_ROOT LIB_DIR
}

export ERROR_DIR_VALIDATION ERROR_INVALID_ARGS ERROR_MISSING_DEPENDENCY
