#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "❌ Usage: $0 <service-name>"
    exit 1
fi

SERVICE_NAME="$1"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT=$(realpath "${SCRIPT_DIR}/..")

# Discover Python (venv vs system)
PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"
if [ ! -f "$PYTHON_CMD" ]; then PYTHON_CMD="python3"; fi

SYSTEMD_DIR="${HOME}/.config/systemd/user"
mkdir -p "${SYSTEMD_DIR}"

echo "🔧 Configuring systemd units for: ${PROJECT_ROOT}"

# Generate the initial .env file via the Python service framework
export PYTHONPATH="${PROJECT_ROOT}:${PYTHONPATH:-}"
${PYTHON_CMD} bin/generate_env.py

# Process the Service template
SERVICE_TEMPLATE="systemd/${SERVICE_NAME}.service.template"
if [ ! -f "${SERVICE_TEMPLATE}" ]; then
    echo "❌ Error: Template not found at ${SERVICE_TEMPLATE}"
    exit 1
fi

# Use | as a delimiter in sed because the path contains slashes
sed "s|{{PROJECT_ROOT}}|${PROJECT_ROOT}|g" \
    "${SERVICE_TEMPLATE}" > "${SYSTEMD_DIR}/${SERVICE_NAME}.service"

# Handle the timer unit (copy as-is, no templating needed)
TIMER_SRC="systemd/${SERVICE_NAME}.timer"
cp "${TIMER_SRC}" "${SYSTEMD_DIR}/"

# Reload systemd and enable the timer
systemctl --user daemon-reload
systemctl --user enable --now "${SERVICE_NAME}.timer"
echo "⏰ Timer enabled: ${SERVICE_NAME}.timer"

echo "🔍 Performing sanity check on ${SERVICE_NAME}..."
# Ask systemd to verify the unit file syntax
systemd-analyze verify "${SYSTEMD_DIR}/${SERVICE_NAME}.service"

echo "✅ Installation complete!"
echo "📡 Monitoring: systemctl --user status ${SERVICE_NAME}.timer"
echo "📊 Logs: journalctl --user -u ${SERVICE_NAME}.service -f"
