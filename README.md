# hermes-pack

Backup and restore your [Hermes Agent](https://hermes-agent.nousresearch.com) environment to/from a private git repo.

## Features

- **Bash CLI** — `hermes-pack.sh` for terminal use
- **MCP Server** — Python MCP server for Claude Desktop, Cursor, and other MCP clients
- **Tagged backups** — version your environment with meaningful names
- **Smart exclusions** — skips bundled skills, caches, secrets, and large DBs (configurable via `exclude-patterns.txt` and `exclude-skills.txt`)
- **Cross-machine restore** — pull your setup onto a new machine in one command

## Install

### One-liner

Installs to `~/hermes-pack` by default.

```bash
bash <(curl -sL https://raw.githubusercontent.com/wayne45/hermes-pack/main/install.sh)
```

### Manual

```bash
git clone https://github.com/wayne45/hermes-pack.git ~/hermes-pack
chmod +x ~/hermes-pack/hermes-pack.sh
```

## CLI Usage

```bash
# Backup
~/hermes-pack/hermes-pack.sh push
~/hermes-pack/hermes-pack.sh push --tag "before-upgrade" --message "full backup"

# Restore
~/hermes-pack/hermes-pack.sh pull git@github.com:user/hermes-backup.git
~/hermes-pack/hermes-pack.sh pull git@github.com:user/hermes-backup.git --version v2

# Manage
~/hermes-pack/hermes-pack.sh delete-tag old-tag
~/hermes-pack/hermes-pack.sh update
```

## MCP Server

For use with Claude Desktop, Cursor, or any MCP-compatible client:

```bash
cd ~/hermes-pack/mcp
uv sync
```

See [mcp/README.md](mcp/README.md) for configuration details.

## Repo Structure

```
hermes-pack/
├── hermes-pack.sh        # Bash CLI (source of truth for logic)
├── install.sh            # One-liner installer
├── exclude-patterns.txt  # File/dir patterns excluded from backup
├── exclude-skills.txt    # Skills excluded from backup (ship with Hermes)
├── README.md
└── mcp/
    ├── pyproject.toml    # Python project (uses uv)
    ├── server.py         # MCP server (thin wrapper over hermes-pack.sh)
    └── README.md         # MCP setup instructions
```

## How It Works

On first run, hermes-pack asks for your private git repo URL (e.g. `git@github.com:user/hermes-backup.git`) and saves it to `~/.hermes/.hermes-pack.conf`. It then creates a local git working tree at `~/.hermes/.hermes-pack-repo` which serves as the staging area for uploads.

1. **Push**: rsync `~/.hermes/` → `~/.hermes/.hermes-pack-repo` (local git working tree) → commit → push to your private repo
2. **Pull**: clone/fetch from private repo → rsync back to `~/.hermes/` → manual secret setup

Key paths:
- **`~/.hermes/.hermes-pack.conf`** — stores your private repo URL (created on first run)
- **`~/.hermes/.hermes-pack-repo/`** — local git staging area for push/pull operations

Excluded from backup (edit these files to customize):
- **`exclude-patterns.txt`** — file/directory patterns (caches, logs, secrets, temp files)
- **`exclude-skills.txt`** — bundled skills reinstalled by `hermes update`

## Requirements

- Git
- Bash 4+
- rsync
- Python 3.10+ and `uv` (for MCP server only)

## License

MIT
