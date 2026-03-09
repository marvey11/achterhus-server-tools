#!/usr/bin/env bash
# shellcheck shell=bash

set -e # Exit on any error

echo "🚀 Initializing Achterhus Server Tools development environment..."

# 1. Install uv if not present
if ! command -v uv &> /dev/null; then
    echo "📦 Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # shellcheck source=/dev/null
    [[ -f "${HOME}/.cargo/env" ]] && source "${HOME}/.cargo/env"
fi

# 2. Sync the environment (includes dev tools like pre-commit)
echo "python Installation and syncing dependencies..."
uv sync --all-extras

# 3. Setup Git hooks
echo "⚓ Installing pre-commit hooks..."
uv run pre-commit install

# 4. Generate the initial .env from .env.json
if [ -f ".env.json" ]; then
    echo "⚙️ Generating .env file..."
    uv run python bin/generate_env.py
fi
