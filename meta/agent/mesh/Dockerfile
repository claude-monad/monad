# monad-agent-mesh — a containerized agent (claude OR codex) that is its own node on the
# Tailscale agent mesh. Build context = meta/agent/mesh/.
#
# Stage 1 builds the tsnet sidecar; stage 2 is the runtime with both engine CLIs.
# Auth at runtime (mounted): ~/.claude + ~/.claude.json (Claude) and ~/.codex (Codex);
# TS_AUTHKEY is templated from secret/agent-mesh by the Nomad job; the repo mounts at /work.
# Runs as non-root 'ubuntu' (uid 1000, matches host) so mounted creds stay usable and the
# engines accept full-access mode.

FROM golang:1.23 AS build
WORKDIR /src
COPY sidecar/go.mod sidecar/go.sum ./
RUN go mod download
COPY sidecar/ ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /tsnet-sidecar .

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        git python3 curl ca-certificates jq nodejs npm \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /work && chown ubuntu:ubuntu /work
COPY --from=build /tsnet-sidecar /usr/local/bin/tsnet-sidecar
COPY agent-msg.sh   /usr/local/bin/agent-msg
COPY entrypoint.sh  /usr/local/bin/agent-entrypoint
RUN chmod +x /usr/local/bin/tsnet-sidecar /usr/local/bin/agent-msg /usr/local/bin/agent-entrypoint
# Codex CLI (global, available to all users)
RUN npm install -g @openai/codex || true
USER ubuntu
WORKDIR /home/ubuntu
RUN curl -fsSL https://claude.ai/install.sh | bash || true
ENV PATH="/home/ubuntu/.local/bin:${PATH}" LOCAL_PORT=8473 MESH_PORT=8472
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/agent-entrypoint"]
