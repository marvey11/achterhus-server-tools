# shellcheck shell=bash

# --- Path Validation Utilities ---

# Validates that a directory exists, and is both writable and searchable.
ensure_writable_dir() {
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
ensure_is_mounted() {
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
