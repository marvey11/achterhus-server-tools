#!/usr/bin/env bash

set -e # Exit on any error

echo "🚀 Initializing Achterhus Server Tools development environment..."

echo "⚓ Installing pre-commit hooks..."
uv run pre-commit install
