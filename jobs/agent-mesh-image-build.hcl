# agent-mesh-image-build — build and push the multi-arch monad-agent-mesh image.
#
# Dispatch after infra/registry exists:
#   nomad job dispatch -meta registry=100.78.218.70:5000 agent-mesh-image-build
#
# The job runs on oraclebox1 because that node currently has the fleet checkout plus a
# healthy Docker driver. The built manifest targets linux/amd64 and linux/arm64 by default.

job "agent-mesh-image-build" {
  datacenters = ["dc1"]
  type        = "batch"

  parameterized {
    payload       = "optional"
    meta_optional = ["registry", "platforms", "image", "tag"]
  }

  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
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
          if [ -z "$repo" ]; then repo="/home/ubuntu/monad"; fi

          cd "$repo"
          git fetch origin main
          git merge --ff-only origin/main

          image="$IMAGE_NAME"
          if [ -z "$image" ]; then image="monad-agent-mesh"; fi

          exec meta/agent/mesh/build-image.sh "$image"
        EOT
        ]
      }

      env {
        MONAD_REPO_DIR = "/home/ubuntu/monad"
        NOMAD_ADDR     = "http://100.125.210.126:4646"
        REGISTRY       = "${NOMAD_META_registry}"
        PLATFORMS      = "${NOMAD_META_platforms}"
        IMAGE_NAME     = "${NOMAD_META_image}"
        TAG            = "${NOMAD_META_tag}"
      }

      resources {
        cpu    = 1000
        memory = 2048
      }

      kill_timeout = "30s"
    }
  }
}
