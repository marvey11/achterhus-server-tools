#!/usr/bin/env bash

set -eu

if [ "$#" -ne 1 ]; then
    echo "❌ Usage: $0 <service-name>"
    exit 1
fi

SERVICE_NAME="$1"

PROJECT_ROOT=$(pwd)
SYSTEMD_DIR="${HOME}/.config/systemd/user"
mkdir -p "${SYSTEMD_DIR}"

echo "🔧 Configuring systemd units for: ${PROJECT_ROOT}"

# Generate the initial .env file via the Python service framework
export PYTHONPATH="${PROJECT_ROOT}:${PYTHONPATH:-}"
python3 bin/generate_env.py

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
# Ask Systemd to verify the unit file syntax
systemd-analyze verify "${SYSTEMD_DIR}/${SERVICE_NAME}.service"

echo "✅ Installation complete!"
echo "📡 Monitoring: systemctl --user status ${SERVICE_NAME}.timer"
echo "📊 Logs: journalctl --user -u ${SERVICE_NAME}.service -f"
