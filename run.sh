#!/bin/bash
# Run Claude Code in Docker with LaTeX support and permission prompts skipped.
# Uses your Claude Max subscription via OAuth tokens from macOS Keychain.
#
# Usage:
#   /w/docker-w/run.sh                         # interactive, starts in /w
#   /w/docker-w/run.sh --workdir /w/pasp       # start in a specific project
#   /w/docker-w/run.sh --workdir /l/l420       # symlinks resolved automatically
#   /w/docker-w/run.sh -p "build Intro420"     # non-interactive single prompt
#
# Mounts:
#   /w        — Samsung SSD /w (rsync'd working copies, read-write)
#   /w-main   — ~/w (original git working copies, read-only reference)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="claude-w"
SSD="/Volumes/Samsung-990-Pro-4TB-2025/w"

# Build image if it doesn't exist
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Building Docker image '$IMAGE_NAME'..."
    docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
fi

# Extract OAuth token from macOS Keychain (Claude Max subscription)
OAUTH_TOKEN=""
if command -v security >/dev/null 2>&1; then
    CREDS=$(security find-generic-password \
        -s "Claude Code-credentials" -a "$(whoami)" -w 2>/dev/null || true)
    if [ -n "$CREDS" ]; then
        OAUTH_TOKEN=$(echo "$CREDS" | python3 -c \
            "import json,sys; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null || true)
    fi
fi

if [ -z "$OAUTH_TOKEN" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "Error: No Claude credentials found."
    echo "  - Claude Max: Keychain entry 'Claude Code-credentials' not found"
    echo "  - API key:    ANTHROPIC_API_KEY not set"
    exit 1
fi

# Resolve symlinks for Docker volume mounts (Docker can't follow host symlinks)
resolve_path() { python3 -c "import os; print(os.path.realpath('$1'))"; }

W_REAL=$(resolve_path "$HOME/w")
CLAUDE_DIR_REAL=$(resolve_path "$HOME/.claude")
CLAUDE_JSON_REAL=$(resolve_path "$HOME/.claude.json")

# Require SSD
if [ ! -d "$SSD" ]; then
    echo "Error: SSD not mounted at $SSD"
    echo "Plug in the Samsung SSD and retry."
    exit 1
fi

# Default working directory inside container
WORKDIR="/w"

# Parse --workdir if given
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workdir)
            WORKDIR="$2"
            shift 2
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# Resolve workdir: if it's a symlinked path like /l/l420, map it into /w/
# e.g. /l/l420 -> /Users/jos/w/lectures420 -> /w/lectures420
WORKDIR_REAL=$(resolve_path "$WORKDIR")
if [[ "$WORKDIR_REAL" == "$W_REAL"* ]]; then
    WORKDIR="/w${WORKDIR_REAL#$W_REAL}"
fi

# Build docker run args
#   /w      = SSD (rsync'd copies — the working area)
#   /w-main = ~/w (read-only reference)
DOCKER_ARGS=(
    -it --rm
    -v "$SSD:/w"
    -v "$W_REAL:/w-main:ro"
    -v "$CLAUDE_DIR_REAL:/home/claude/.claude"
    -v "$CLAUDE_JSON_REAL:/home/claude/.claude.json"
    -v "$HOME/.gitconfig:/home/claude/.gitconfig:ro"
)

# Pass OAuth token from Keychain
if [ -n "$OAUTH_TOKEN" ]; then
    DOCKER_ARGS+=(-e "CLAUDE_CODE_OAUTH_TOKEN=$OAUTH_TOKEN")
fi

# Pass API key if set (fallback)
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    DOCKER_ARGS+=(-e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
fi

DOCKER_ARGS+=(-w "$WORKDIR")

exec docker run "${DOCKER_ARGS[@]}" \
    "$IMAGE_NAME" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
