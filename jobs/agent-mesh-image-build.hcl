# agent-mesh-image-build — build and push the multi-arch monad-agent-mesh image.
#
# Dispatch after infra/registry exists:
#   nomad job dispatch -meta registry=100.78.218.70:5000 agent-mesh-image-build
#
# The job runs on bigo-server because that node hosts the shared registry, has a healthy
# Docker driver, and exposes the fleet checkout as a host volume. The built manifest targets
# linux/amd64 and linux/arm64 by default.

job "agent-mesh-image-build" {
  datacenters = ["dc1"]
  type        = "batch"

  parameterized {
    payload       = "optional"
    meta_optional = ["registry", "platforms", "image", "tag"]
  }

  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  group "build" {
    count = 1

    task "build" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args = ["-lc", <<-EOT
          set -euo pipefail

          repo="$MONAD_REPO_DIR"
          if [ -z "$repo" ]; then
            for candidate in /home/bigo/Documents/monad /home/ubuntu/monad /home/bigo/monad /work; do
              [ -d "$candidate/.git" ] || continue
              repo="$candidate"
              break
            done
          fi
          if [ -z "$repo" ]; then
            echo "agent-mesh-image-build: no monad repo checkout found" >&2
            exit 1
          fi

          cd "$repo"
          git config --global --add safe.directory "$repo" || true
          git -c safe.directory="$repo" fetch origin main
          git -c safe.directory="$repo" merge --ff-only origin/main

          image="$IMAGE_NAME"
          if [ -z "$image" ]; then image="monad-agent-mesh"; fi

          exec meta/agent/mesh/build-image.sh "$image"
        EOT
        ]
      }

      env {
        MONAD_REPO_DIR = "/home/bigo/Documents/monad"
        NOMAD_ADDR     = "http://100.125.210.126:4646"
        REGISTRY       = "${NOMAD_META_registry}"
        PLATFORMS      = "${NOMAD_META_platforms}"
        IMAGE_NAME     = "${NOMAD_META_image}"
        TAG            = "${NOMAD_META_tag}"
        AGENT_UID      = "1001"
        AGENT_GID      = "1001"
      }

      resources {
        cpu    = 500
        memory = 2048
      }

      kill_timeout = "30s"
    }
  }
}
