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

## Container mounts

| Container path | Host source | Contents |
|----------------|-------------|----------|
| `/w` | `~/w` | All git working copies (read-write) |
| `/ssd` | Samsung SSD `.../w` | rsync'd copies + large data files (read-write, mounted only if SSD is plugged in) |
| `/home/claude/.claude` | `~/.claude` | Claude Code settings, memory, history |
| `/home/claude/.claude.json` | `~/.claude.json` | Claude Code config/state |

Symlinked host paths (e.g. `/l/l420` -> `~/w/lectures420`) are resolved
automatically and mapped into `/w/...` inside the container.

## Sandboxing

**What's contained:**
- Can't access your home directory, SSH keys, browser data, or anything outside the mounts
- If it runs `rm -rf /`, only container internals are destroyed

**What's exposed (read-write):**
- `/w` -- untracked files (build outputs, temp files) could be deleted; git-tracked files are recoverable
- `/ssd` -- same risk as `/w`
- `~/.claude`, `~/.claude.json` -- conversation history, settings could be corrupted

**Network:** unrestricted. Could `git push` (HTTPS only -- no SSH keys mounted) or curl arbitrary URLs.

**Mitigations:**
- Mount `~/.claude` read-only: add `:ro` to the volume flags in `run.sh`
- Rsync projects to the SSD and work on the copy (`--workdir /ssd/pasp`)
- `git stash --include-untracked` before a session to protect untracked files

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
