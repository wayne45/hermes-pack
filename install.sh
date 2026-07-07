#!/usr/bin/env bash
set -euo pipefail

# hermes-pack installer
# Usage: bash <(curl -sL https://raw.githubusercontent.com/wayne45/hermes-pack/main/install.sh)

INSTALL_DIR="$HOME/hermes-pack"
REPO_URL="https://github.com/wayne45/hermes-pack"
ARCHIVE_URL="$REPO_URL/archive/refs/heads/main.tar.gz"

echo "Installing hermes-pack to $INSTALL_DIR ..."

TMPDIR_DL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_DL"' EXIT

curl -sL "$ARCHIVE_URL" | tar xz -C "$TMPDIR_DL"

mkdir -p "$INSTALL_DIR"

# Copy files from archive, preserving existing local config
cp -f "$TMPDIR_DL/hermes-pack-main/hermes-pack.sh" "$INSTALL_DIR/"
cp -f "$TMPDIR_DL/hermes-pack-main/README.md" "$INSTALL_DIR/"
cp -f "$TMPDIR_DL/hermes-pack-main/install.sh" "$INSTALL_DIR/"

# Copy mcp directory
if [[ -d "$TMPDIR_DL/hermes-pack-main/mcp" ]]; then
    cp -rf "$TMPDIR_DL/hermes-pack-main/mcp" "$INSTALL_DIR/"
fi

# Remove .git if leftover from previous git-based install
rm -rf "$INSTALL_DIR/.git"

chmod +x "$INSTALL_DIR/hermes-pack.sh"

echo ""
echo "✓ hermes-pack installed at $INSTALL_DIR"
echo ""
echo "Usage:"
echo "  ~/hermes-pack/hermes-pack.sh push"
echo "  ~/hermes-pack/hermes-pack.sh pull <repo-url>"
echo ""
echo "Optional — add alias to your shell rc:"
echo "  echo 'alias hermes-pack=\"~/hermes-pack/hermes-pack.sh\"' >> ~/.zshrc"
echo ""
echo "MCP server (optional):"
echo "  cd ~/hermes-pack/mcp && uv sync"
echo "  See mcp/README.md for Claude Desktop configuration"
echo ""
