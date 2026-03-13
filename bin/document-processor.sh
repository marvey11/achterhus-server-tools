#!/usr/bin/env bash

set -euo pipefail

# --- CONFIGURATION ---
SERVICE_NAME="document-processor"
METADATA="{}" # Default to empty JSON object

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT=$(realpath "${SCRIPT_DIR}/..")

# Discover Python (venv vs system)
PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"
if [ ! -f "$PYTHON_CMD" ]; then PYTHON_CMD="python3"; fi

function finish() {
    local exit_code=$?

    ${PYTHON_CMD} "${SCRIPT_DIR}/service_status.py" \
        "${SERVICE_NAME}" \
        "$exit_code" \
        --metadata "$METADATA"

    if [ "$exit_code" -ne 0 ]; then
        echo "❌ Document processing failed with exit code $exit_code."
    fi
}


trap finish EXIT INT TERM

ENV_FILE="${PROJECT_ROOT}/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️ .env not found, attempting to generate..."
    ${PYTHON_CMD} "${SCRIPT_DIR}/generate_env.py" || {
        echo "❌ Failed to generate .env file."
        exit 1
    }
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

: "${DOCUMENT_INBOX:?Variable DOCUMENT_INBOX is not set or empty}"
: "${DOCUMENT_STORAGE:?Variable DOCUMENT_STORAGE is not set or empty}"

export DOCUMENT_STORAGE

# Enable associative arrays
declare -A stats
stats=()  # Initialize empty stats array
export stats

# shellcheck source-path=./lib
LIB_DIR="${PROJECT_ROOT}/lib"
# shellcheck source=../lib/utils.sh
source "${LIB_DIR}/utils.sh"

echo "--- Document Processing Started: $(date) ---"

PROCESSOR_DIR="${LIB_DIR}/document-processor"
for proc in "$PROCESSOR_DIR"/*.sh; do
    [ -e "$proc" ] || continue
    # shellcheck source=../lib/document-processor/comdirect.sh
    # shellcheck source=../lib/document-processor/ryd.sh
    # shellcheck source=../lib/document-processor/vodafone.sh
    source "$proc"
done

# --- MAIN LOOP ---
for dir in "${DOCUMENT_INBOX}"/*; do
    [ -d "$dir" ] || continue

    category=$(basename "$dir")
    processor="process_${category}"

    # Initialize count for this category
    stats["$category"]=0

    if declare -f "$processor" > /dev/null; then
        for file in "$dir"/*.pdf; do
            [ -e "$file" ] || continue

            # Execute processor and increment count if successful
            if "$processor" "$file"; then
                # IMPORTANT: arithmetic expressions can trigger `set -e` if
                # they evaluate to 0 --> therefore, we use `|| true` here
                ((stats["$category"]++)) || true
            fi
        done
    else
        echo "[$(date)] WARNING: No processor found for $category."
    fi
done

file_count=0

for cat in "${!stats[@]}"; do
    cat_count="${stats[$cat]}"
    file_count=$((file_count + cat_count))
done

METADATA=$(cat <<EOF
{
  "images": {
    "label": "Processed",
    "value": ${file_count},
    "unit": " files"
  }
}
EOF
)

echo "--- Document Processing Finished: $(date) ---"
