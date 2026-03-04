#!/bin/bash
# Docker entrypoint: fix platform symlinks, then run Claude Code.

# If Makefile.lecture points to -macosx, switch to -linux for Docker
if [ -L "$PWD/Makefile.lecture" ]; then
    target=$(readlink "$PWD/Makefile.lecture")
    if [[ "$target" == *macosx* ]] && [ -f "$PWD/Makefile.lecture-linux" ]; then
        ln -sf Makefile.lecture-linux "$PWD/Makefile.lecture"
    fi
fi

exec claude --dangerously-skip-permissions "$@"
