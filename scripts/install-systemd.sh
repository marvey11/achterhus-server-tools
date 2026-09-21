#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "❌ Usage: $0 <service-name>"
    exit 1
fi

SERVICE_NAME="$1"

echo "🔧 Configuring systemd units for: ${SERVICE_NAME}"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SYSTEMD_DIR=$(realpath "${SCRIPT_DIR}/../systemd")
CONFIG_DIR="${HOME}/.config/achterhus/server-tools"
USER_SYSTEMD_DIR="${HOME}/.config/systemd/user"

mkdir -p "${USER_SYSTEMD_DIR}" "${CONFIG_DIR}"

SERVICE_CONFIG=${CONFIG_DIR}/${SERVICE_NAME}.env

if [[ ! -f ${SERVICE_CONFIG} ]]; then
    cp "${SYSTEMD_DIR}/${SERVICE_CONFIG}-example" "${SERVICE_CONFIG}"
    echo "Created ${SERVICE_CONFIG} from the example template. Update it before enabling the timer."
fi

# Symlink unit files so updates in the repository are reflected automatically.
ln -sfn "${SYSTEMD_DIR}/${SERVICE_NAME}.service" "${USER_SYSTEMD_DIR}/${SERVICE_NAME}.service"
ln -sfn "${SYSTEMD_DIR}/${SERVICE_NAME}.timer" "${USER_SYSTEMD_DIR}/${SERVICE_NAME}.timer"

echo "🔍 Performing sanity check on ${SERVICE_NAME}..."
# Ask systemd to verify the unit file syntax
systemd-analyze verify --user "${SERVICE_NAME}.service"
systemd-analyze verify --user "${SERVICE_NAME}.timer"

# Reload systemd and enable the timer
systemctl --user daemon-reload
systemctl --user enable --now "${SERVICE_NAME}.timer"
echo "⏰ Timer enabled: ${SERVICE_NAME}.timer"

echo "✅ Installation complete!"
echo "📡 Monitoring: systemctl --user status ${SERVICE_NAME}.timer"
echo "📊 Logs: journalctl --user -u ${SERVICE_NAME}.service -f"
