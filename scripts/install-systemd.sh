#!/usr/bin/env bash

set -euo pipefail

# --- Pre-checks & Argument Validation ---

if [[ "${#}" -ne 1 ]]; then
    echo "❌ Usage: $0 <service-name>" >&2
    exit 1
fi

SERVICE_NAME="${1}"

# Resolve repository paths safely
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SYSTEMD_DIR="$(realpath "${SCRIPT_DIR}/../systemd")"
CONFIG_DIR="${HOME}/.config/achterhus"
USER_SYSTEMD_DIR="${HOME}/.config/systemd/user"

SERVICE_CONFIG="${CONFIG_DIR}/server-tools.env"
EXAMPLE_CONFIG="${SYSTEMD_DIR}/server-tools.env-example"

SERVICE_UNIT="${SYSTEMD_DIR}/${SERVICE_NAME}.service"
TIMER_UNIT="${SYSTEMD_DIR}/${SERVICE_NAME}.timer"

# Verify source unit files exist before proceeding
if [[ ! -f "${SERVICE_UNIT}" ]]; then
    echo "❌ Error: Systemd service unit not found: ${SERVICE_UNIT}" >&2
    exit 1
fi

if [[ ! -f "${TIMER_UNIT}" ]]; then
    echo "❌ Error: Systemd timer unit not found: ${TIMER_UNIT}" >&2
    exit 1
fi

echo "🔧 Configuring systemd units for: ${SERVICE_NAME}"

# Ensure user systemd and config directories exist
mkdir -p "${USER_SYSTEMD_DIR}" "${CONFIG_DIR}"

# --- Configuration Setup ---

if [[ ! -f "${SERVICE_CONFIG}" ]]; then
    if [[ -f "${EXAMPLE_CONFIG}" ]]; then
        cp "${EXAMPLE_CONFIG}" "${SERVICE_CONFIG}"
        chmod 600 "${SERVICE_CONFIG}"
        echo "📝 Created ${SERVICE_CONFIG} from example template."
        echo "⚠️  Please update ${SERVICE_CONFIG} before proceeding."
    else
        echo "⚠️  Warning: Example config template not found at ${EXAMPLE_CONFIG}" >&2
    fi
fi

# --- Symlink Unit Files ---

ln -sfn "${SERVICE_UNIT}" "${USER_SYSTEMD_DIR}/${SERVICE_NAME}.service"
ln -sfn "${TIMER_UNIT}" "${USER_SYSTEMD_DIR}/${SERVICE_NAME}.timer"

# --- Verification & Systemd Deployment ---

echo "🔍 Performing sanity check on ${SERVICE_NAME}..."
systemd-analyze verify --user "${USER_SYSTEMD_DIR}/${SERVICE_NAME}.service"
systemd-analyze verify --user "${USER_SYSTEMD_DIR}/${SERVICE_NAME}.timer"

systemctl --user daemon-reload
systemctl --user enable --now "${SERVICE_NAME}.timer"

echo "⏰ Timer enabled: ${SERVICE_NAME}.timer"
echo "✅ Installation complete!"
echo "📡 Monitoring: systemctl --user status ${SERVICE_NAME}.timer"
echo "📊 Logs:       journalctl --user -u ${SERVICE_NAME}.service -f"
