#!/usr/bin/env bash

set -euo pipefail

# Configuration
SERVICE_NAME="backup-postgres"
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
        echo "❌ Database backup failed with exit code $exit_code."
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

: "${DATABASE_ARCHIVE:?Variable DATABASE_ARCHIVE is not set or empty}"
: "${POSTGRES_USER:?Variable POSTGRES_USER is not set or empty}"
: "${POSTGRES_DB:?Variable POSTGRES_DB is not set or empty}"

mkdir -p "${DATABASE_ARCHIVE}"

echo "--- Database Backup Started: $(date) ---"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${DATABASE_ARCHIVE}/achterhus_db_${TIMESTAMP}.sql.gz"

docker exec achterhus_db pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" | gzip > "${BACKUP_FILE}"

BACKUP_SIZE=$(du -sh "${BACKUP_FILE}" | cut -f1)
SAFE_FILESIZE="${BACKUP_SIZE:-unknown}"

METADATA=$(cat <<EOF
{
  "backup_size": {
    "label": "Backup File Size",
    "value": "${SAFE_FILESIZE}"
  }
}
EOF
)

echo "--- Database Backup Finished: $(date) ---"
