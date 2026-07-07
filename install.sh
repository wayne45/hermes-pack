#!/usr/bin/env bash
set -euo pipefail

# hermes-pack installer
# Usage: bash <(curl -sL https://raw.githubusercontent.com/waynehuang/hermes-pack/main/install.sh)

INSTALL_DIR="$HOME/hermes-pack"

echo "Installing hermes-pack to $INSTALL_DIR ..."

if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "Already installed. Updating..."
    cd "$INSTALL_DIR"
    git pull origin main
else
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "Directory exists but is not a git repo. Removing and re-cloning..."
        rm -rf "$INSTALL_DIR"
    fi
    git clone https://github.com/waynehuang/hermes-pack.git "$INSTALL_DIR"
fi

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
