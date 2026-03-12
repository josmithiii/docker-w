#!/bin/bash
# Run Claude Code in Docker with LaTeX support and permission prompts skipped.
# Uses your Claude Max subscription via OAuth tokens from macOS Keychain.
#
# Usage:
#   /w/docker-w/run.sh                         # interactive, starts in /w
#   /w/docker-w/run.sh --workdir /w/pasp       # start in a specific project
#   /w/docker-w/run.sh --workdir /l/l420       # symlinks resolved automatically
#   /w/docker-w/run.sh -p "build Intro420"     # non-interactive single prompt
#   /w/docker-w/run.sh --continue               # resume previous conversation
#   /w/docker-w/run.sh --memory 8g              # set container memory limit
#   /w/docker-w/run.sh --rebuild --cc-version 2.1.12  # pin Claude Code version
#   /w/docker-w/run.sh --logs                   # list stopped sessions + how to view logs
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
CONTINUE_FLAG=""
MEMORY_LIMIT=""
CC_VERSION=""
FORCE_REBUILD=false

# Clean up stopped containers from previous sessions (preserves last session's logs)
OLD_CONTAINERS=$(docker ps -a --filter "name=claude-w-" --filter "status=exited" -q 2>/dev/null)
if [ -n "$OLD_CONTAINERS" ]; then
    echo "Cleaning up $(echo "$OLD_CONTAINERS" | wc -l | tr -d ' ') old container(s)..."
    docker rm $OLD_CONTAINERS >/dev/null
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

# Parse arguments
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workdir)
            WORKDIR="$2"
            shift 2
            ;;
        --continue)
            CONTINUE_FLAG="--continue"
            shift
            ;;
        --memory)
            MEMORY_LIMIT="$2"
            shift 2
            ;;
        --cc-version)
            CC_VERSION="$2"
            shift 2
            ;;
        --rebuild)
            FORCE_REBUILD=true
            shift
            ;;
        --logs)
            echo "Stopped claude-w containers:"
            docker ps -a --filter "name=claude-w-" --filter "status=exited" \
                --format 'table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}'
            echo ""
            echo "View logs:  docker logs <name>"
            echo "Tail logs:  docker logs --tail 50 <name>"
            exit 0
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# Build image if needed (after arg parsing so --rebuild and --cc-version are available)
NEED_BUILD=false
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    NEED_BUILD=true
fi
if [ "$FORCE_REBUILD" = true ]; then
    NEED_BUILD=true
fi
if [ "$NEED_BUILD" = true ]; then
    echo "Building Docker image '$IMAGE_NAME'..."
    BUILD_ARGS=()
    if [ -n "$CC_VERSION" ]; then
        echo "  Claude Code version: $CC_VERSION"
        BUILD_ARGS+=(--build-arg "CC_VERSION=$CC_VERSION")
    fi
    docker build "${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}" -t "$IMAGE_NAME" "$SCRIPT_DIR"
fi

# Resolve workdir: if it's a symlinked path like /l/l420, map it into /w/
# e.g. /l/l420 -> /Users/jos/w/lectures420 -> /w/lectures420
WORKDIR_REAL=$(resolve_path "$WORKDIR")
if [[ "$WORKDIR_REAL" == "$W_REAL"* ]]; then
    WORKDIR="/w${WORKDIR_REAL#$W_REAL}"
fi

CONTAINER_NAME="claude-w-$(basename "$WORKDIR")-$$"

# Build docker run args
#   /w      = SSD (rsync'd copies — the working area)
#   /w-main = ~/w (read-only reference)
DOCKER_ARGS=(
    -it
    --name "$CONTAINER_NAME"
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

# Container memory limit
if [ -n "$MEMORY_LIMIT" ]; then
    DOCKER_ARGS+=(--memory "$MEMORY_LIMIT")
    echo "Memory: limit set to $MEMORY_LIMIT"
fi

# Let container reach host services (e.g. local LLM, Docker Model Runner)
DOCKER_ARGS+=(--add-host=host.docker.internal:host-gateway)

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
NOTIFY_WATCHER_PID=""

cleanup() {
    # Stop the Docker container (handles terminal close / SIGHUP)
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    # Give watcher time to detect .notify-done before killing it
    sleep 2
    [ -n "$NOTIFY_WATCHER_PID" ] && kill "$NOTIFY_WATCHER_PID" 2>/dev/null || true
    [ -n "$SOCAT_MAC_PID" ] && kill "$SOCAT_MAC_PID" 2>/dev/null || true
    # Killing the colima ssh session kills the VM-side socat via SIGHUP
    [ -n "$SOCAT_COLIMA_SSH_PID" ] && kill "$SOCAT_COLIMA_SSH_PID" 2>/dev/null || true
    rm -f "$CLAUDE_DIR_REAL/.notify-done-docker"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Notification watcher: container touches ~/.claude/.notify-done-docker → Mac says it
# ---------------------------------------------------------------------------
rm -f "$CLAUDE_DIR_REAL/.notify-done-docker"
(while true; do
    if [ -f "$CLAUDE_DIR_REAL/.notify-done-docker" ]; then
        rm -f "$CLAUDE_DIR_REAL/.notify-done-docker"
        say "CLAUDE CODE DOCKER DONE"
    fi
    sleep 1
done) &
NOTIFY_WATCHER_PID=$!
echo "Notify: watcher active (say on task completion)"

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
# Pass --continue flag to claude via environment variable
if [ -n "$CONTINUE_FLAG" ]; then
    DOCKER_ARGS+=(-e "CLAUDE_CONTINUE_FLAG=--continue")
fi

docker run "${DOCKER_ARGS[@]}" \
    "$IMAGE_NAME" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
