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
    meta_optional = ["registry", "platforms", "image", "tag", "uid", "gid"]
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
          build_repo="$(mktemp -d /tmp/monad-agent-mesh-build.XXXXXX)"
          cleanup() {
            cd /
            git -C "$repo" worktree remove --force "$build_repo" >/dev/null 2>&1 || rm -rf "$build_repo"
          }
          trap cleanup EXIT
          git -c safe.directory="$repo" worktree add --detach "$build_repo" origin/main >/dev/null
          cd "$build_repo"

          image="$IMAGE_NAME"
          if [ -z "$image" ]; then image="monad-agent-mesh"; fi

          meta/agent/mesh/build-image.sh "$image"
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
        # Per-host uid/gid for the in-image `ubuntu` user so host-mounted mode-600 creds are
        # readable on nodes where the credentialed user isn't uid 1001. Empty (no -meta uid)
        # falls back to 1001 (oraclebox1) via build-image.sh's defaults. See
        # fleet/projects/amd64-agent-uid-image.md.
        AGENT_UID      = "${NOMAD_META_uid}"
        AGENT_GID      = "${NOMAD_META_gid}"
      }

      resources {
        cpu    = 500
        memory = 2048
      }

      kill_timeout = "30s"
    }
  }
}
