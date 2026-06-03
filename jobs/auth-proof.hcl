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
          U=claude; H="$(getent passwd "$U" | cut -d: -f6)"
          P="/usr/local/bin:/snap/bin:$H/.local/bin:/usr/bin:/bin"
          echo "=== auth-proof on $(hostname) as $U ==="
          echo "claude bin: $(su - "$U" -c "PATH=$P command -v claude" 2>&1)"
          echo "codex  bin: $(su - "$U" -c "PATH=$P command -v codex" 2>&1)"
          echo "--- claude (distributed token) ---"
          timeout 90 su - "$U" -c "PATH=$P claude --print --dangerously-skip-permissions 'Reply with exactly: CLAUDE_AUTH_OK'" 2>&1 | tail -3
          echo "--- codex (distributed token) ---"
          timeout 120 su - "$U" -c "PATH=$P codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check 'Reply with exactly: CODEX_AUTH_OK'" 2>&1 | tail -4
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
