# docker-w

Docker environment for running [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
with `--dangerously-skip-permissions` (no interactive approval prompts).
Includes a full TeX Live installation for building LaTeX projects.

Authenticates via your **Claude Max subscription** (OAuth token extracted
from macOS Keychain at runtime -- no API key needed).

## Quick start

```bash
# Build the image (first time only, ~10 min for TeX Live)
docker build -t claude-latex /w/docker-w/

# Interactive session, starting in ~/w
/w/docker-w/run.sh

# Start in a specific project
/w/docker-w/run.sh --workdir /w/pasp
/w/docker-w/run.sh --workdir /l/l420    # symlinks resolved automatically

# Non-interactive single prompt
/w/docker-w/run.sh -p "build the Intro420 lecture"
```

## Prerequisites

**Colima** (Docker VM for macOS) with `vz`/`virtiofs` and the SSD mount:

```bash
brew install colima
```

Edit `~/.colima/default/colima.yaml`:

```yaml
vmType: vz
mountType: virtiofs
mounts:
  - location: /Volumes/Samsung-990-Pro-4TB-2025/w
    writable: true
  - location: /Users/jos
    writable: true
```

Then `colima start`. The two mount paths must not overlap (mount the SSD
subdirectory `.../w`, not the whole volume).

**Samsung SSD** must be plugged in. Rsync what you need before starting:

```bash
rsync -a ~/w/pasp/ /Volumes/Samsung-990-Pro-4TB-2025/w/pasp/
```

## Container mounts

| Container path | Host source | Mode | Contents |
|----------------|-------------|------|----------|
| `/w` | Samsung SSD `.../w` | read-write | rsync'd working copies (the working area) |
| `/w-main` | `~/w` | **read-only** | Original git working copies (reference) |
| `/home/claude/.claude` | `~/.claude` | read-write | Claude Code settings, memory, history |
| `/home/claude/.claude.json` | `~/.claude.json` | read-write | Claude Code config/state |

Symlinked host paths (e.g. `/l/l420` -> `~/w/lectures420`) are resolved
automatically and mapped into `/w/...` inside the container.

## Sandboxing

**What's contained:**
- Can't access your home directory, SSH keys, browser data, or anything outside the mounts
- If it runs `rm -rf /`, only container internals are destroyed

**What's exposed (read-write):**
- `/w` (SSD) -- untracked files could be deleted, but these are rsync'd copies; originals in `~/w` are safe (mounted read-only as `/w-main`)
- `~/.claude`, `~/.claude.json` -- conversation history, settings could be corrupted

**Network:** unrestricted. Could `git push` (HTTPS only -- no SSH keys mounted) or curl arbitrary URLs.

**Mitigations:**
- Mount `~/.claude` read-only: add `:ro` to the volume flags in `run.sh`
- `~/w` is already read-only; the SSD copy is expendable (re-rsync to restore)

## Authentication

`run.sh` extracts the OAuth access token from your macOS Keychain
(`Claude Code-credentials`) and passes it via the `CLAUDE_CODE_OAUTH_TOKEN`
environment variable. No secrets are stored in these files.

Fallback: set `ANTHROPIC_API_KEY` in your environment to use an API key instead.

## Adding packages

**Pre-installed (persistent):** add to the `apt-get install` list in `Dockerfile`, then rebuild:

```bash
docker build -t claude-latex /w/docker-w/
```

Docker caches unchanged layers, so rebuilds only re-run from the changed line onward.

**At runtime (ephemeral):** the Dockerfile grants the `claude` user passwordless
sudo, so Claude Code (or you via its shell) can install packages during a session:

```
sudo apt-get update && sudo apt-get install -y ffmpeg
```

These disappear when the container exits -- useful for one-off experiments.

**Rule of thumb:** packages you always want go in the Dockerfile;
everything else can be installed at runtime as needed.

## LaTeX build notes

The entrypoint auto-switches `Makefile.lecture` symlinks from `-macosx`
to `-linux` when detected, so `make pdf` etc. work inside the container.

Included TeX/build packages: texlive-latex-{base,recommended,extra},
texlive-{fonts-recommended,fonts-extra,science,pictures}, ghostscript,
netpbm, psutils, transfig, latex2html.
