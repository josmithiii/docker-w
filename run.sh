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
#   ~/.ssh    — SSH keys (read-only, for git push/pull)
#
# X11 forwarding (automatic when XQuartz is running):
#   Chain: container → Colima VM socat (172.17.0.1:6000)
#                    → Mac socat (port 6001)
#                    → XQuartz Unix socket
#   Requires: socat installed on Mac (brew install socat)

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
    -v "$HOME/.ssh:/home/claude/.ssh:ro"
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

# ---------------------------------------------------------------------------
# X11 forwarding via two-hop socat chain (automatic when XQuartz is running)
#
# The chain:
#   container (DISPLAY=172.17.0.1:0)
#     → Colima VM socat  (172.17.0.1:6000 → host.lima.internal:6001)
#     → Mac socat        (TCP:6001 → XQuartz Unix socket)
#     → XQuartz
# ---------------------------------------------------------------------------
SOCAT_MAC_PID=""
SOCAT_COLIMA_SSH_PID=""

cleanup_x11() {
    [ -n "$SOCAT_MAC_PID" ] && kill "$SOCAT_MAC_PID" 2>/dev/null || true
    # Killing the colima ssh session kills the VM-side socat via SIGHUP
    [ -n "$SOCAT_COLIMA_SSH_PID" ] && kill "$SOCAT_COLIMA_SSH_PID" 2>/dev/null || true
}
trap cleanup_x11 EXIT

# Auto-detect XQuartz: DISPLAY set and pointing at a launchd socket
if [[ "${DISPLAY:-}" == /private/tmp/* ]]; then
    if ! command -v socat >/dev/null 2>&1; then
        echo "X11: socat not found (brew install socat) — skipping X11 forwarding"
    else
        # Kill any stale socat from a previous run
        pkill -f "socat.*TCP-LISTEN:6001" 2>/dev/null || true
        sleep 0.2

        # Mac socat: expose XQuartz Unix socket as TCP:6001
        # Escape the colon in the launchd socket path (e.g. org.xquartz:0)
        SOCK=$(printf '%s' "$DISPLAY" | sed 's/:/\\:/g')
        socat TCP-LISTEN:6001,reuseaddr,fork "UNIX-CLIENT:$SOCK" &
        SOCAT_MAC_PID=$!

        # Colima VM socat: bridge docker0 (172.17.0.1:6000) → Mac:6001
        # Runs in background via SSH; SSH exit kills the VM-side socat via SIGHUP
        colima ssh -- \
            sudo socat TCP-LISTEN:6000,bind=172.17.0.1,reuseaddr,fork \
            TCP:host.lima.internal:6001 &
        SOCAT_COLIMA_SSH_PID=$!

        sleep 0.5
        DOCKER_ARGS+=(-e "DISPLAY=172.17.0.1:0")
        echo "X11: Forwarding XQuartz → container (DISPLAY=172.17.0.1:0)"
        echo "X11: Run 'xhost +' in XQuartz terminal if windows don't appear"
    fi
fi

# ---------------------------------------------------------------------------
# Launch container (not exec so EXIT trap fires for X11 cleanup)
# ---------------------------------------------------------------------------
docker run "${DOCKER_ARGS[@]}" \
    "$IMAGE_NAME" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
