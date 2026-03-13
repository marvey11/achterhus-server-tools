# shellcheck shell=bash

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
