#!/usr/bin/env bash
set -e

HOOK_DIR=$(git rev-parse --show-toplevel)/.githooks

if [ -d "$HOOK_DIR" ]; then
    git config core.hooksPath .githooks
    chmod +x .githooks/* 2>/dev/null || true
    echo "✅ Git hooks configured to use .githooks directory."
else
    echo "❌ Error: .githooks directory not found!"
    exit 1
fi
