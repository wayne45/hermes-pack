#!/usr/bin/env bash
set -euo pipefail

# hermes-pack: Pack and restore Hermes agent environment to/from a private git repo.
# Usage:
#   hermes-pack push [--message "msg"] [--tag <name>]
#   hermes-pack pull <repo-url> [--version <tag/hash>]

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_PACK_HOME="$(cd "$(dirname "$0")" && pwd)"
PACK_CONF="$HERMES_HOME/.hermes-pack.conf"
PACK_REPO="$HERMES_HOME/.hermes-pack-repo"
EXCLUDE_SKILLS="$HERMES_PACK_HOME/exclude-skills.txt"
EXCLUDE_PATTERNS="$HERMES_PACK_HOME/exclude-patterns.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[info]${NC} $*"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
error() { echo -e "${RED}[error]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

# Load saved repo URL
load_config() {
    if [[ -f "$PACK_CONF" ]]; then
        source "$PACK_CONF"
    fi
}

# Save config
save_config() {
    cat > "$PACK_CONF" <<EOF
PACK_REMOTE_URL="$PACK_REMOTE_URL"
PACK_GIT_EMAIL="${PACK_GIT_EMAIL:-}"
EOF
}

# Ask for repo URL if not configured
ensure_repo_url() {
    load_config
    if [[ -z "${PACK_REMOTE_URL:-}" ]]; then
        echo ""
        echo "First time setup — need a private git repo URL."
        echo "Create an empty private repo on GitHub first, then paste the URL here."
        echo ""
        read -rp "Repo URL (e.g. git@github.com:user/hermes-backup.git): " PACK_REMOTE_URL
        [[ -z "$PACK_REMOTE_URL" ]] && die "Repo URL is required."
        read -rp "Git email for commits (leave empty to use global): " PACK_GIT_EMAIL
        save_config
        ok "Saved config to $PACK_CONF"
    fi
}

# Build the exclude list for rsync
build_exclude_list() {
    local exclude_file
    exclude_file=$(mktemp)

    # Load patterns from external file
    if [[ -f "$EXCLUDE_PATTERNS" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue
            echo "$line" >> "$exclude_file"
        done < "$EXCLUDE_PATTERNS"
    else
        die "Exclude patterns file not found: $EXCLUDE_PATTERNS"
    fi

    # Exclude bundled skills
    if [[ -f "$EXCLUDE_SKILLS" ]]; then
        while IFS= read -r skill || [[ -n "$skill" ]]; do
            # Skip comments and empty lines
            [[ "$skill" =~ ^#.*$ ]] && continue
            [[ -z "$skill" ]] && continue
            # Find the skill directory path relative to ~/.hermes/
            find "$HERMES_HOME/skills" -type d -name "$skill" 2>/dev/null | while read -r dir; do
                local rel
                rel="${dir#$HERMES_HOME/}"
                echo "${rel}/" >> "$exclude_file"
            done
        done < "$EXCLUDE_SKILLS"
    fi

    echo "$exclude_file"
}

# Initialize the pack repo
init_pack_repo() {
    if [[ ! -d "$PACK_REPO/.git" ]]; then
        info "Initializing pack repo at $PACK_REPO"
        mkdir -p "$PACK_REPO"
        cd "$PACK_REPO"
        git init -q
        git remote add origin "$PACK_REMOTE_URL" 2>/dev/null || git remote set-url origin "$PACK_REMOTE_URL"
        # Try to pull existing content
        if git ls-remote origin &>/dev/null; then
            git fetch origin 2>/dev/null || true
            if git rev-parse origin/main &>/dev/null; then
                git checkout -b main origin/main 2>/dev/null || true
            else
                git checkout -b main 2>/dev/null || true
            fi
        else
            git checkout -b main 2>/dev/null || true
        fi
        ok "Pack repo initialized"
    else
        cd "$PACK_REPO"
        git remote set-url origin "$PACK_REMOTE_URL"
    fi

    # Apply git email if configured
    if [[ -n "${PACK_GIT_EMAIL:-}" ]]; then
        git config user.email "$PACK_GIT_EMAIL"
    fi
}

# Generate manifest
generate_manifest() {
    local hermes_version
    hermes_version=$(hermes --version 2>/dev/null || echo "unknown")
    local skill_count
    skill_count=$(find "$PACK_REPO/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local os_info
    os_info=$(uname -s -r -m)

    cat > "$PACK_REPO/manifest.json" <<EOF
{
  "packed_at": "$timestamp",
  "hermes_version": "$hermes_version",
  "os": "$os_info",
  "hostname": "$(hostname)",
  "custom_skills_count": $skill_count,
  "includes_sessions": $(if [[ -f "$PACK_REPO/state.db.gz" ]] || [[ -f "$PACK_REPO/state.db" ]]; then echo "true"; else echo "false"; fi)
}
EOF
}

# ============================================================
# PUSH
# ============================================================
cmd_push() {
    local message=""
    local tag=""
    local branch="main"

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message)     message="$2"; shift 2 ;;
            --tag)         tag="$2"; shift 2 ;;
            --branch)      branch="$2"; shift 2 ;;
            *)             die "Unknown option: $1" ;;
        esac
    done

    ensure_repo_url
    init_pack_repo

    info "Syncing hermes environment to pack repo..."

    # Build exclude list
    local exclude_file
    exclude_file=$(build_exclude_list)

    # Rsync hermes home to pack repo (excluding items)
    rsync -a --delete \
        --exclude=".git/" \
        --exclude-from="$exclude_file" \
        "$HERMES_HOME/" "$PACK_REPO/"

    rm -f "$exclude_file"

    # Remove .git dirs from synced skills (they shouldn't be nested repos)
    find "$PACK_REPO" -mindepth 2 -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

    # Git add and commit
    cd "$PACK_REPO"

    # Switch to target branch
    git checkout "$branch" 2>/dev/null || git checkout -b "$branch"

    # Generate manifest
    generate_manifest
    git add -A

    # Check if there are changes
    if git diff --cached --quiet; then
        ok "No changes to push."
        return 0
    fi

    # Commit
    if [[ -z "$message" ]]; then
        message="hermes-pack push $(date +%Y-%m-%d_%H:%M:%S)"
    fi
    git commit -q -m "$message"

    # Tag if requested
    if [[ -n "$tag" ]]; then
        git tag -a "$tag" -m "$message"
        info "Tagged as: $tag"
    fi

    # Push
    info "Pushing to remote..."
    git push -u origin "$branch" --tags 2>&1 | sed 's/^/  /'

    echo ""
    ok "Push complete!"
    echo ""
    echo "  Commit: $(git rev-parse --short HEAD)"
    [[ -n "$tag" ]] && echo "  Tag: $tag"
    echo "  Remote: $PACK_REMOTE_URL"
    echo ""
}

# ============================================================
# PULL
# ============================================================
cmd_pull() {
    local repo_url=""
    local version=""

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) version="$2"; shift 2 ;;
            -*)        die "Unknown option: $1" ;;
            *)
                if [[ -z "$repo_url" ]]; then
                    repo_url="$1"
                else
                    die "Unexpected argument: $1"
                fi
                shift
                ;;
        esac
    done

    # Determine repo URL
    load_config
    if [[ -n "$repo_url" ]]; then
        PACK_REMOTE_URL="$repo_url"
        save_config
    elif [[ -z "${PACK_REMOTE_URL:-}" ]]; then
        die "No repo URL. Usage: hermes-pack pull <repo-url> [--version <tag/hash>]"
    fi

    info "Pulling from $PACK_REMOTE_URL"

    # Clone or fetch
    if [[ -d "$PACK_REPO/.git" ]]; then
        cd "$PACK_REPO"
        git remote set-url origin "$PACK_REMOTE_URL"
        git fetch origin --tags
    else
        rm -rf "$PACK_REPO"
        git clone -q "$PACK_REMOTE_URL" "$PACK_REPO"
        cd "$PACK_REPO"
    fi

    # Checkout version if specified
    if [[ -n "$version" ]]; then
        info "Checking out version: $version"
        git checkout "$version" 2>/dev/null || die "Version '$version' not found."
    else
        git checkout main 2>/dev/null || git checkout master 2>/dev/null || true
        git pull origin "$(git branch --show-current)" --rebase 2>/dev/null || true
    fi

    # Show manifest
    if [[ -f "$PACK_REPO/manifest.json" ]]; then
        echo ""
        info "Manifest:"
        cat "$PACK_REPO/manifest.json" | sed 's/^/  /'
        echo ""
    fi

    # Backup current hermes home (critical files only)
    local backup_dir="$HERMES_HOME/.hermes-pack-backup"
    rm -rf "$backup_dir"
    mkdir -p "$backup_dir"
    for f in config.yaml SOUL.md; do
        [[ -f "$HERMES_HOME/$f" ]] && cp "$HERMES_HOME/$f" "$backup_dir/"
    done
    info "Current config backed up to $backup_dir"

    # Decompress state.db if present
    if [[ -f "$PACK_REPO/state.db.gz" ]]; then
        info "Decompressing state.db..."
        gunzip -k -f "$PACK_REPO/state.db.gz"
    fi

    # Rsync from pack repo to hermes home
    rsync -a \
        --exclude=".git/" \
        --exclude="state.db.gz" \
        --exclude="manifest.json" \
        "$PACK_REPO/" "$HERMES_HOME/"

    # Remove the decompressed state.db from pack repo (keep only .gz)
    rm -f "$PACK_REPO/state.db"

    # Fix permissions on restored files
    chmod 700 "$HERMES_HOME"
    [[ -f "$HERMES_HOME/state.db" ]] && chmod 600 "$HERMES_HOME/state.db"

    echo ""
    ok "Pull complete! Environment restored."
    echo ""
    warn "ACTION REQUIRED — set up secrets manually:"
    echo ""
    echo "  1. Edit API keys:"
    echo "     \$ hermes config env-path   # shows .env location"
    echo "     \$ nano \$(hermes config env-path)"
    echo ""
    echo "  2. Set up authentication:"
    echo "     \$ hermes auth"
    echo ""
    echo "  3. Install/update Hermes runtime:"
    echo "     \$ hermes update"
    echo ""
    echo "  4. (Optional) Verify:"
    echo "     \$ hermes doctor"
    echo ""
}

# ============================================================
# DELETE-TAG
# ============================================================
cmd_delete_tag() {
    local tag="${1:-}"
    [[ -z "$tag" ]] && die "Usage: hermes-pack delete-tag <name>"

    load_config
    [[ -z "${PACK_REMOTE_URL:-}" ]] && die "No repo configured. Run push first."

    if [[ ! -d "$PACK_REPO/.git" ]]; then
        die "Pack repo not found. Run push first."
    fi

    cd "$PACK_REPO"

    # Delete local tag
    if git tag -l "$tag" | grep -q "$tag"; then
        git tag -d "$tag"
        ok "Deleted local tag: $tag"
    else
        warn "Local tag '$tag' not found."
    fi

    # Delete remote tag
    if git ls-remote --tags origin | grep -q "refs/tags/$tag"; then
        git push origin --delete "$tag" 2>&1 | sed 's/^/  /'
        ok "Deleted remote tag: $tag"
    else
        warn "Remote tag '$tag' not found."
    fi
}

# ============================================================
# UPDATE (self-update)
# ============================================================
cmd_update() {
    info "Updating hermes-pack..."
    cd "$HERMES_PACK_HOME"
    git pull origin main 2>&1 | sed 's/^/  /'
    ok "hermes-pack updated!"
}

# ============================================================
# CLEAN
# ============================================================
cmd_clean() {
    warn "This will remove all hermes-pack local data:"
    echo "  - $PACK_REPO"
    echo "  - $PACK_CONF"
    echo "  - $HERMES_HOME/.hermes-pack-backup"
    echo ""
    read -rp "Continue? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Cancelled."; return 0; }

    rm -rf "$PACK_REPO"
    rm -f "$PACK_CONF"
    rm -rf "$HERMES_HOME/.hermes-pack-backup"
    ok "Cleaned. You can now run 'hermes-pack push' or 'hermes-pack pull' with a new repo."
}

# ============================================================
# MAIN
# ============================================================
usage() {
    echo "hermes-pack — Pack and restore Hermes agent environment"
    echo ""
    echo "Usage:"
    echo "  hermes-pack push [--message \"msg\"] [--tag <name>] [--branch <name>]"
    echo "  hermes-pack pull <repo-url> [--version <tag/hash>]"
    echo "  hermes-pack delete-tag <name>"
    echo "  hermes-pack update"
    echo "  hermes-pack clean"
    echo ""
    echo "Examples:"
    echo "  hermes-pack push --tag \"before-upgrade\" --message \"full backup\""
    echo "  hermes-pack pull git@github.com:user/hermes-backup.git"
    echo "  hermes-pack pull --version v2"
    echo "  hermes-pack delete-tag test-v1"
}

case "${1:-}" in
    push)       shift; cmd_push "$@" ;;
    pull)       shift; cmd_pull "$@" ;;
    delete-tag) shift; cmd_delete_tag "$@" ;;
    clean)      shift; cmd_clean ;;
    update)     shift; cmd_update ;;
    -h|--help|help|"") usage ;;
    *)     die "Unknown command: $1. Use 'hermes-pack --help'" ;;
esac
