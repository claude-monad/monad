# mesh-conversation — a PERSISTENT reactive LLM on the mesh (not a one-shot demo).
#
# Dispatched per persona (scripts/mesh-convo.sh launch <name> "<role>" [node]). Runs
# meta/agent/mesh/mesh-agent-loop.sh as the node's engine-credentialed user: registers on the
# mesh relay, long-polls (idle = free, no token burn), and the instant a peer messages it,
# replies in real time with an engine-generated response. This is how the cluster's LLMs stay
# in live communication. Cost-safe by design: an idle agent costs nothing; it only spends
# tokens when it actually has a message to answer.
#
#   nomad job dispatch -meta name=lrc-coord -meta role="..." -meta node=death-star mesh-conversation

job "mesh-conversation" {
  datacenters = ["dc1"]
  type        = "batch"
  priority    = 70

  parameterized {
    payload       = "optional"
    meta_required = ["name", "role"]
    meta_optional = ["engine", "node", "greet"]
  }

  meta {
    node   = "death-star"
    engine = "codex"
    greet  = ""
  }

  constraint {
    attribute = "${node.unique.name}"
    value     = "${NOMAD_META_node}"
  }

  group "agent" {
    count = 1
    reschedule {
      attempts       = 0
      delay          = "15s"
      delay_function = "exponential"
      max_delay      = "2m"
      unlimited      = true
    }
    restart {
      attempts = 3
      interval = "10m"
      delay    = "15s"
      mode     = "delay"
    }

    network { mode = "host" }

    task "loop" {
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        args    = ["local/run.sh"]
      }

      env {
        AGENT_NAME = "agent-${NOMAD_META_name}"
        AGENT_ROLE = "${NOMAD_META_role}"
        MONAD_ENGINE = "${NOMAD_META_engine}"
        AGENT_GREET  = "${NOMAD_META_greet}"
        MESH_RELAY   = "http://100.75.75.39:8477"
        NOMAD_ADDR   = "http://100.75.75.39:4646"
      }

      template {
        destination = "local/run.sh"
        perms       = "755"
        data        = <<-SCRIPT
          #!/bin/bash
          set -uo pipefail
          W=/tmp/mesh-convo-$${NOMAD_META_name}-monad
          if [ -d "$W/.git" ]; then git -C "$W" fetch -q origin main && git -C "$W" reset --hard -q origin/main || true
          else rm -rf "$W"; git clone -q --depth 1 https://github.com/eliott-monad/monad "$W"; fi
          # Pick the engine-credentialed user (codex creds, else claude) and run the loop as them
          # so the engine authenticates; drop via su (provisioner unlocks the user).
          pick(){ local u h r; r=$([ "$MONAD_ENGINE" = claude ] && echo .claude/.credentials.json || echo .codex/auth.json)
            for u in claude ubuntu e eliott bigo $(getent passwd|awk -F: '$3>=1000 && $3<65000{print $1}'); do
              h="$(getent passwd "$u" 2>/dev/null|cut -d: -f6)"; [ -n "$h" ] || continue
              [ -f "$h/$r" ] && { echo "$u"; return; }; done; id -un; }
          U="$(pick)"
          ENVS="AGENT_NAME='$AGENT_NAME' AGENT_ROLE='$AGENT_ROLE' MONAD_ENGINE='$MONAD_ENGINE' AGENT_GREET='$AGENT_GREET' MESH_RELAY='$MESH_RELAY' NOMAD_ADDR='$NOMAD_ADDR'"
          CMD="export PATH=/usr/local/bin:\$HOME/.local/bin:/snap/bin:/usr/bin:/bin; $ENVS exec bash '$W/meta/agent/mesh/mesh-agent-loop.sh'"
          echo "[mesh-convo] $AGENT_NAME engine=$MONAD_ENGINE user=$U node=$(hostname)"
          if [ "$(id -un)" = "$U" ]; then exec bash -c "$CMD"
          elif [ "$(id -u)" = 0 ]; then exec su - "$U" -c "$CMD"
          else exec sudo -n -u "$U" -H bash -c "$CMD"; fi
        SCRIPT
      }

      resources {
        cpu    = 150
        memory = 300
      }
      kill_timeout = "8s"
    }
  }
}
