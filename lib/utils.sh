# shellcheck shell=bash

# Verify required commands exist in $PATH
function check_dependencies() {
    local dep
    for dep in "$@"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            printf 'Error: Required dependency "%s" is not installed or not in PATH.\n' "$dep" >&2
            return "$ERROR_MISSING_DEP"
        fi
    done
}

function run_and_log() {
    if [[ $# -eq 0 ]]; then
        printf 'Error: run_and_log requires a command to execute.\n' >&2
        return 1
    fi

    : "${STATS_FILE:?STATS_FILE variable must be set}"
    : "${ERROR_LOG:?ERROR_LOG variable must be set}"

    local status=0
    "$@" 2>&1 | tee "$STATS_FILE" "$ERROR_LOG" || status=$?

    if [[ "$status" -ne 0 ]]; then
        # Check if code is allowed as a warning
        for code in "${ALLOWED_WARN_CODES[@]}"; do
            if [[ "$status" -eq "$code" ]]; then
                printf 'Notice: Command exited with non-fatal code %d.\n' "$status" >&2
                return 0
            fi
        done

        printf 'Error: Executable "%s" exited with code %d.\n' "$1" "$status" >&2
        return "$status"
    fi
}

# Validates that a directory exists, and is both writable and searchable.
function ensure_writable_dir() {
    local dir="$1"
    local label="${2:-Directory}"

    # Check if directory exists
    if [[ ! -d "$dir" ]]; then
        echo "❌ Error: $label '$dir' does not exist" >&2
        return 1
    fi

    # Check Permissions: -w (writable), -x (searchable/executable for dirs)
    if [[ ! -w "$dir" ]]; then
        echo "❌ Error: $label '$dir' is not writable by current user ($(whoami))" >&2
        return 1
    fi

    if [[ ! -x "$dir" ]]; then
        echo "❌ Error: $label '$dir' is not accessible (missing +x bit)" >&2
        return 1
    fi

    return 0
}

# Validates that a directory exists, and is mounted.
function ensure_is_mounted() {
    local dir="$1"
    local label="${2:-Directory}"
    local current


    if [[ ! -d "$dir" ]]; then
        echo "❌ Error: $label '$dir' does not exist!" >&2
        return 1
    fi

    # Iterates over the directory to be tested and its parents to check if either is a mount point.
    current="$dir"
    while [[ "$current" != "/" ]]; do
        if mountpoint -q "$current"; then
            # Success! Found the mount point for this path.
            return 0
        fi
        current=$(dirname "$current")
    done

    echo "❌ Error: $label '$dir' is not mounted!" >&2
    return 1
}

# Moves file and verifies integrity before deletion
function move_and_verify() {
    local src="$1"
    local t_dir="$2"
    local t_name="$3"
    local t_path="$t_dir/$t_name"

    mkdir -p "$t_dir" || return 1

    # if [ -f "$t_path" ]; then
    #     echo "File exists: $t_path"
    #     return 0
    # fi

    # If the copy fails, stop here and return an error
    if ! cp -p "$src" "$t_path"; then
        echo "[$(date)] ERROR: Failed to copy $src to $t_path"
        return 1
    fi

    local src_hash
    local dest_hash

    src_hash=$(sha256sum "$src" | awk '{print $1}')
    dest_hash=$(sha256sum "$t_path" | awk '{print $1}')

    if [ "$src_hash" == "$dest_hash" ]; then
        rm "$src"
        echo "[$(date)] SUCCESS: Sorted $(basename "$src") -> $t_path"

        return 0
    else
        # Critical: Remove the corrupted/incomplete copy so we don't have bad data
        rm -f "$t_path"
        echo "[$(date)] ERROR: Hash mismatch for $(basename "$src")! File left in inbox."

        return 1
    fi
}

function generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [ -r /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        jq -rn '
            [range(16)] | map(if . == 6 then (random * 16 | floor | . % 16 | . + 64)
                              elif . == 8 then (random * 16 | floor | . % 4 | . + 128)
                              else (random * 256 | floor) end)
            | map(if . < 16 then "0" else "" end + tostring) | join("")
            | "\(.[0:8])-\(.[8:12])-\(.[12:16])-\(.[16:20])-\(.[20:32])"
        '
    fi
}

function get_iso8601() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}
