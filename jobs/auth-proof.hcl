# auth-proof — one-shot: run a REAL claude + codex call on claudebox using only the
# distributed creds (it never logged in itself). Proves cross-machine token validity.
# Read: nomad alloc logs <alloc>
job "auth-proof" {
  datacenters = ["dc1"]
  type        = "batch"

  constraint {
    attribute = "${node.unique.name}"
    value     = "claudebox"
  }

  group "p" {
    count = 1
    restart {
      attempts = 0
      mode     = "fail"
    }
    reschedule {
      attempts  = 0
      unlimited = false
    }

    task "probe" {
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        args    = ["local/run.sh"]
      }
      template {
        destination = "local/run.sh"
        perms       = "755"
        data        = <<-SCRIPT
          #!/bin/bash
          set -uo pipefail
          # raw_exec may run as the node's run-user (e.g. 'claude' on claudebox) rather than root,
          # so run engines DIRECTLY as whoever we are — never su to self (that prompts a password).
          ME="$(id -un)"; H="$HOME"
          export PATH="/usr/local/bin:/snap/bin:$H/.local/bin:$H/.claude/local:/usr/bin:/bin:$PATH"
          echo "=== auth-proof on $(hostname) as $ME (home=$H) ==="
          echo "claude bin: $(command -v claude 2>&1)"
          echo "codex  bin: $(command -v codex 2>&1)"
          echo "creds: $(ls -la "$H/.claude/.credentials.json" "$H/.codex/auth.json" 2>&1 | awk '{print $NF}' | tr '\n' ' ')"
          echo "--- claude (distributed token) ---"
          command -v claude >/dev/null && timeout 90 claude --print --dangerously-skip-permissions 'Reply with exactly: CLAUDE_AUTH_OK' 2>&1 | tail -3 || echo "(claude not on PATH)"
          echo "--- codex (distributed token) ---"
          command -v codex >/dev/null && timeout 120 codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check 'Reply with exactly: CODEX_AUTH_OK' 2>&1 | tail -4 || echo "(codex not on PATH)"
          echo "=== done ==="
        SCRIPT
      }
      resources {
        cpu    = 300
        memory = 512
      }
    }
  }
}
