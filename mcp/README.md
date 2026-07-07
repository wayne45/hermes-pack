# hermes-pack MCP Server

MCP server that exposes hermes-pack operations as tools for any MCP-compatible client.

## Setup

```bash
cd ~/hermes-pack/mcp
uv sync
```

## Available Tools

| Tool | Description |
|------|-------------|
| `push` | Backup Hermes environment to remote (optional message, tag) |
| `pull` | Restore from remote (optional repo_url, version) |
| `delete_tag` | Delete a backup tag |
| `list_tags` | List all available backup tags with dates |
| `status` | Show configured repo, last push, tag count |
| `show_manifest` | Show manifest from last push |

## Claude Desktop Configuration

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "hermes-pack": {
      "command": "uv",
      "args": ["run", "--directory", "/Users/YOU/hermes-pack/mcp", "python", "server.py"],
      "env": {
        "HERMES_HOME": "/Users/YOU/.hermes"
      }
    }
  }
}
```

Replace `YOU` with your username.

## Cursor / Other MCP Clients

Use the stdio transport. The server binary after `uv sync`:

```bash
cd ~/hermes-pack/mcp && uv run python server.py
```

## Development

```bash
cd ~/hermes-pack/mcp
uv sync
uv run mcp dev server.py   # launches MCP Inspector for testing
```
