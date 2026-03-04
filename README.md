2026-03-04 - CCO session: 53886a2c-fa39-469a-b977-3cf0663bb543

> ... suppose instead of /l/l420 I want to work on /w/pasp/ - what is the procedure?

⏺ ./docker/run.sh --workdir /w/pasp

> How "sandboxed" is [the docker container]? ... I'm not worried about git-tracked directories, but what else could go wrong if anything?

⏺ Good question. Here's the realistic threat model:

  What's safe (contained by Docker)

  - Can't touch your home directory, system files, or anything outside the mounted volumes
  - Can't access other projects, SSH keys, browser cookies, etc.
  - If it runs rm -rf /, only container internals are destroyed

  What's exposed (read-write mounts)

  ┌──────────────────────┬───────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │        Mount         │                                                     Risk                                                      │
  ├──────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ /l/l420              │ Untracked files (build outputs, temp files, local notes) could be deleted. Git-tracked files are recoverable. │
  ├──────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ /workspace/jos-latex │ Same -- untracked files at risk.                                                                               │
  ├──────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ ~/.claude            │ Your full conversation history, memory, plugins, hooks, project settings. Could be corrupted or wiped.        │
  ├──────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ ~/.claude.json       │ 190KB of Claude Code settings/state. Could be modified.                                                       │
  └──────────────────────┴───────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  Network

  The container has unrestricted network access. Claude Code could:
  - git push (though SSH keys aren't mounted, so only HTTPS with cached creds)
  - Curl arbitrary URLs
  - Send data anywhere

  The official devcontainer reference includes a firewall script for this reason, but we didn't add one.

  Practical recommendations

  1. Mount .claude read-only if you only need Claude to work on LaTeX (it won't be able to save memory/history, but that's fine for a sandboxed session):

  -v "$CLAUDE_DIR_REAL:/home/claude/.claude:ro"
  -v "$CLAUDE_JSON_REAL:/home/claude/.claude.json:ro"

  2. Restrict network if you want tighter sandboxing:

  docker run --network=none ...   # no network at all (won't work -- needs API)

  Or allow only the Claude API:
  # In run.sh, add:
  --add-host=host.docker.internal:host-gateway
  (Full firewall requires iptables in the entrypoint -- the official init-firewall.sh does this.)

  3. The real risk: untracked files in /l/l420 that aren't in git. If
     you have any precious untracked work there, a rogue make tclean
     or rm could destroy it. You could mitigate with a snapshot:

  cd /l/l420 && git stash --include-untracked   # before Docker session

  Bottom line: For your use case (editing LaTeX, building PDFs), the
  main practical risk is accidental deletion of untracked files in the
  two mounted project directories. Everything else on your system is
  invisible to the container.
