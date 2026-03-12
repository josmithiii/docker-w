# Claude Code + LaTeX development environment
# Build:  docker build -t claude-w /w/docker-w/
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
# C++ build tools and JUCE Linux dependencies
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    ninja-build \
    clang \
    libc++-dev \
    libc++abi-dev \
    g++ \
    pkg-config \
    libasound2-dev \
    libjack-jackd2-dev \
    libfreetype-dev \
    libx11-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxcursor-dev \
    libxcomposite-dev \
    libgl-dev \
    libcurl4-openssl-dev \
    libwebkit2gtk-4.1-dev \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Non-root user (required by --dangerously-skip-permissions)
# ============================================================================
RUN useradd -m -s /bin/bash claude \
    && echo "claude ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
RUN mkdir -p /w /ssd && chown claude:claude /w /ssd

# ============================================================================
# Claude Code (optionally pin version with --build-arg CC_VERSION=2.1.12)
# ============================================================================
ARG CC_VERSION=""
RUN if [ -n "$CC_VERSION" ]; then \
        npm install -g @anthropic-ai/claude-code@$CC_VERSION; \
    else \
        npm install -g @anthropic-ai/claude-code; \
    fi

USER claude
WORKDIR /w

# ============================================================================
# Entry point
# ============================================================================
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# Default: interactive Claude Code with permissions skipped
ENTRYPOINT ["entrypoint.sh"]
