# Claude Code + LaTeX development environment
# Build:  docker build -t claude-latex /w/docker-w/
# Run:    /w/docker-w/run.sh

FROM node:20-bookworm

# ============================================================================
# LaTeX (large, slow-changing — cached as its own layer)
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    texlive-latex-base \
    texlive-latex-recommended \
    texlive-latex-extra \
    texlive-fonts-recommended \
    texlive-fonts-extra \
    texlive-science \
    texlive-pictures \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Build tools and utilities (add new packages here to avoid TeX Live rebuild)
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    ghostscript \
    netpbm \
    psutils \
    transfig \
    latex2html \
    sudo \
    git \
    curl \
    jq \
    perl \
    procps \
    less \
    vim-tiny \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Non-root user (required by --dangerously-skip-permissions)
# ============================================================================
RUN useradd -m -s /bin/bash claude \
    && echo "claude ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
RUN mkdir -p /w /ssd && chown claude:claude /w /ssd

# ============================================================================
# Claude Code
# ============================================================================
RUN npm install -g @anthropic-ai/claude-code

USER claude
WORKDIR /w

# ============================================================================
# Entry point
# ============================================================================
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# Default: interactive Claude Code with permissions skipped
ENTRYPOINT ["entrypoint.sh"]
