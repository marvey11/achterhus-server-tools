#!/usr/bin/env bash

# Strict error handling
set -euo pipefail

SCRIPTS_DIR="/opt/achterhus-server-tools/app/services"

# Helper for formatted error logging
log_error() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

# Ensure at least one argument was passed
if [ "$#" -eq 0 ]; then
    log_error "No command provided."
    echo "Usage: docker run --rm <image> <command> [args...]" >&2
    echo "Available commands:" >&2
    if [ -d "$SCRIPTS_DIR" ]; then
        find "$SCRIPTS_DIR" -maxdepth 1 -name "*.sh" -exec basename {} .sh \; | sort | sed 's/^/  /' >&2
    fi
    exit 1
fi

COMMAND="$1"
shift

SCRIPT_PATH="${SCRIPTS_DIR}/${COMMAND}.sh"

# Validate that the script exists and is executable
if [ ! -f "$SCRIPT_PATH" ]; then
    log_error "Unknown command '${COMMAND}'."
    exit 1
elif [ ! -x "$SCRIPT_PATH" ]; then
    log_error "Command '${COMMAND}' exists but is not executable."
    exit 1
fi

# Replace entrypoint process so the target script receives SIGTERM/SIGINT directly
exec "$SCRIPT_PATH" "$@"
