"""
hermes-pack MCP Server

Exposes hermes-pack operations as MCP tools so any MCP client
(Claude Desktop, Cursor, etc.) can trigger backups/restores.

This is a thin wrapper — all logic lives in hermes-pack.sh.
"""

import asyncio
import json
import os
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP

# Locate hermes-pack.sh relative to this file
SCRIPT_DIR = Path(__file__).parent.parent
HERMES_PACK_SH = SCRIPT_DIR / "hermes-pack.sh"
HERMES_HOME = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))

mcp = FastMCP(
    "hermes-pack",
    instructions="Backup and restore Hermes agent environment to/from a private git repo",
)


async def run_hermes_pack(*args: str) -> dict:
    """Run hermes-pack.sh with given arguments and return structured output."""
    cmd = [str(HERMES_PACK_SH)] + list(args)

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env={**os.environ, "NO_COLOR": "1"},  # disable ANSI colors for clean output
    )
    stdout, stderr = await proc.communicate()

    result = {
        "exit_code": proc.returncode,
        "stdout": stdout.decode().strip(),
        "stderr": stderr.decode().strip(),
    }

    if proc.returncode != 0:
        result["error"] = True

    return result


@mcp.tool()
async def push(message: str = "", tag: str = "") -> str:
    """Push (backup) the Hermes agent environment to the configured private git repo.

    Args:
        message: Optional commit message for the backup.
        tag: Optional tag name to label this backup (e.g. "before-upgrade", "v2").
    """
    args = ["push"]
    if message:
        args.extend(["--message", message])
    if tag:
        args.extend(["--tag", tag])

    result = await run_hermes_pack(*args)

    if result.get("error"):
        return f"Push failed:\n{result['stderr']}\n{result['stdout']}"
    return result["stdout"]


@mcp.tool()
async def pull(repo_url: str = "", version: str = "") -> str:
    """Pull (restore) the Hermes agent environment from a private git repo.

    Args:
        repo_url: Git repo URL to pull from. Required on first use, saved for subsequent calls.
        version: Optional tag or commit hash to restore a specific version.
    """
    args = ["pull"]
    if repo_url:
        args.append(repo_url)
    if version:
        args.extend(["--version", version])

    result = await run_hermes_pack(*args)

    if result.get("error"):
        return f"Pull failed:\n{result['stderr']}\n{result['stdout']}"
    return result["stdout"]


@mcp.tool()
async def delete_tag(tag: str) -> str:
    """Delete a backup tag from both local and remote.

    Args:
        tag: The tag name to delete.
    """
    result = await run_hermes_pack("delete-tag", tag)

    if result.get("error"):
        return f"Delete tag failed:\n{result['stderr']}\n{result['stdout']}"
    return result["stdout"]


@mcp.tool()
async def status() -> str:
    """Show the current hermes-pack status: configured repo, last push, available tags."""
    lines = []

    # Check config
    conf_path = HERMES_HOME / ".hermes-pack.conf"
    if conf_path.exists():
        content = conf_path.read_text()
        for line in content.splitlines():
            if line.startswith("PACK_REMOTE_URL="):
                url = line.split("=", 1)[1].strip('"').strip("'")
                lines.append(f"Remote: {url}")
                break
    else:
        lines.append("Remote: not configured (run push first)")
        return "\n".join(lines)

    # Check pack repo
    pack_repo = HERMES_HOME / ".hermes-pack-repo"
    if pack_repo.exists() and (pack_repo / ".git").exists():
        # Last commit
        try:
            result = subprocess.run(
                ["git", "log", "-1", "--format=%h %s (%ci)"],
                cwd=str(pack_repo),
                capture_output=True,
                text=True,
            )
            if result.returncode == 0 and result.stdout.strip():
                lines.append(f"Last push: {result.stdout.strip()}")
        except Exception:
            pass

        # Tags
        try:
            result = subprocess.run(
                ["git", "tag", "-l", "--sort=-creatordate"],
                cwd=str(pack_repo),
                capture_output=True,
                text=True,
            )
            if result.returncode == 0 and result.stdout.strip():
                tags = result.stdout.strip().splitlines()
                lines.append(f"Tags ({len(tags)}): {', '.join(tags[:10])}")
                if len(tags) > 10:
                    lines.append(f"  ... and {len(tags) - 10} more")
            else:
                lines.append("Tags: none")
        except Exception:
            lines.append("Tags: unable to list")

        # Check for uncommitted changes (diff since last push)
        try:
            # Quick check: compare current hermes home vs last push
            result = subprocess.run(
                ["git", "status", "--porcelain"],
                cwd=str(pack_repo),
                capture_output=True,
                text=True,
            )
            # This shows status of pack repo itself, not live changes
            # For live drift detection we'd need to do a dry-run rsync
            pass
        except Exception:
            pass
    else:
        lines.append("Pack repo: not initialized (run push first)")

    return "\n".join(lines) if lines else "No status information available."


@mcp.tool()
async def list_tags() -> str:
    """List all available backup tags with their dates and messages."""
    pack_repo = HERMES_HOME / ".hermes-pack-repo"

    if not pack_repo.exists() or not (pack_repo / ".git").exists():
        return "Pack repo not initialized. Run push first."

    try:
        result = subprocess.run(
            [
                "git",
                "tag",
                "-l",
                "--sort=-creatordate",
                "--format=%(refname:short)  %(creatordate:short)  %(subject)",
            ],
            cwd=str(pack_repo),
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return f"Available tags:\n{result.stdout.strip()}"
        else:
            return "No tags found."
    except Exception as e:
        return f"Error listing tags: {e}"


@mcp.tool()
async def show_manifest() -> str:
    """Show the manifest from the last push (versions, OS, skill count)."""
    pack_repo = HERMES_HOME / ".hermes-pack-repo"
    manifest_path = pack_repo / "manifest.json"

    if not manifest_path.exists():
        return "No manifest found. Run push first."

    try:
        data = json.loads(manifest_path.read_text())
        lines = ["Last backup manifest:", ""]
        for key, value in data.items():
            lines.append(f"  {key}: {value}")
        return "\n".join(lines)
    except Exception as e:
        return f"Error reading manifest: {e}"


def main():
    mcp.run()


if __name__ == "__main__":
    main()
