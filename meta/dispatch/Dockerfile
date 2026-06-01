# monad-claude-session — a containerized, headless Claude research session.
# Auth at runtime: mount the host's ~/.claude + ~/.claude.json (Claude OAuth) and
# pass GH_TOKEN (from `gh auth token`) for git push. The container clones the repo
# fresh, so concurrent sessions are fully isolated (no shared working tree).
#
# Runs as the base image's non-root 'ubuntu' user (uid 1000) — Claude refuses
# --dangerously-skip-permissions as root. uid 1000 matches the host 'ubuntu' user
# so mounted credential files stay readable/writable (token refresh works).
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        git python3 python3-pip curl ca-certificates jq \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /work && chown ubuntu:ubuntu /work
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
USER ubuntu
WORKDIR /home/ubuntu
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/ubuntu/.local/bin:${PATH}"
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
