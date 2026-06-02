# monad-agent-mesh — a containerized agent (claude OR codex) that is its own node on the
# Tailscale agent mesh. Build context = meta/agent/mesh/.
#
# Stage 1 builds the tsnet sidecar; stage 2 is the runtime with both engine CLIs.
# Auth at runtime (mounted): ~/.claude + ~/.claude.json (Claude) and ~/.codex (Codex);
# TS_AUTHKEY is templated from secret/agent-mesh by the Nomad job; the repo mounts at /work.
# Runs as non-root 'ubuntu' (uid 1001, matches oraclebox1) so mounted creds stay usable and the
# engines accept full-access mode.

FROM --platform=$BUILDPLATFORM golang:1.23 AS build
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY sidecar/go.mod sidecar/go.sum ./
RUN go mod download
COPY sidecar/ ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o /tsnet-sidecar .

FROM --platform=$TARGETPLATFORM node:22-bookworm-slim AS node

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        git python3 curl ca-certificates jq \
    && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/bin/npm /usr/local/bin/npm
COPY --from=node /usr/local/bin/npx /usr/local/bin/npx
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
# Match the 'ubuntu' user to the HOST's uid/gid so mounted creds (mode 600) are readable
# and the in-image claude install lands in a home the runtime user owns. Default 1001
# (oraclebox1's ubuntu); override with --build-arg AGENT_UID=/AGENT_GID= for other hosts.
ARG AGENT_UID=1001
ARG AGENT_GID=1001
RUN if [ "$(id -u ubuntu)" != "${AGENT_UID}" ]; then \
        groupmod -g ${AGENT_GID} ubuntu && usermod -u ${AGENT_UID} -g ${AGENT_GID} ubuntu; \
    fi && chown -R ${AGENT_UID}:${AGENT_GID} /home/ubuntu
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
