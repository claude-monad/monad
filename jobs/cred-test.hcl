# cred-test — one-shot proof that distributed creds let an engine run on a node that never
# logged in. Pinned to a target node; installs claude+codex creds from the encrypted var store
# (meta/agent/cred-sync.sh) into the primary user's home, then smoke-tests both engines and
# prints the result to stdout (read via: nomad alloc logs <alloc>). Safe: cred-sync is
# newest-wins, so it won't clobber a node's own fresher login; a --print call uses the existing
# access token (no refresh, no token rotation).
#
# Retarget by editing the node value below, then: nomad job run jobs/cred-test.hcl

job "cred-test" {
  datacenters = ["dc1"]
  type        = "batch"

  constraint {
    attribute = "${node.unique.name}"
    value     = "claudebox"
  }

  group "test" {
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
          export NOMAD_ADDR="$${NOMAD_ADDR:-http://100.75.75.39:4646}"
          echo "=== cred-test on $(hostname) ==="
          U=""; for u in e ubuntu eliott bigo; do getent passwd "$u" >/dev/null 2>&1 && { U="$u"; break; }; done
          # Fallback: first real login user (uid>=1000, has a /home dir, not 'nobody').
          if [ -z "$U" ]; then
            U="$(getent passwd | awk -F: '$3>=1000 && $3<65000 && $6 ~ /^\/home\// {print $1; exit}')"
          fi
          echo "detected users on box: $(getent passwd | awk -F: '$3>=1000 && $3<65000{print $1}' | tr '\n' ' ')"
          [ -n "$U" ] || { echo "no candidate user"; exit 1; }
          H="$(getent passwd "$U" | cut -d: -f6)"
          echo "user=$U home=$H"

          W=/tmp/credtest-monad
          rm -rf "$W"; git clone -q --depth 1 https://github.com/eliott-monad/monad "$W" || { echo "clone failed"; exit 1; }

          echo "--- BEFORE: does $U already have creds? ---"
          ls -la "$H/.claude/.credentials.json" "$H/.codex/auth.json" 2>&1 | sed 's/^/  /' || true

          echo "--- install creds from store (newest-wins) ---"
          CRED_USER="$U" bash "$W/meta/agent/cred-sync.sh" install claude pro --user "$U"
          CRED_USER="$U" bash "$W/meta/agent/cred-sync.sh" install codex  pro --user "$U"

          echo "--- locate existing binaries (claude logged in here at 04:25, so one exists) ---"
          find "$H" /usr/local/bin /usr/bin /opt /snap -maxdepth 6 -name claude -type f 2>/dev/null | head -5
          find "$H" /usr/local/bin /usr/bin /opt /snap -maxdepth 6 -name codex  -type f 2>/dev/null | head -5
          echo "  login PATH: $(su - "$U" -c 'echo $PATH')"
          echo "  curl present: $(command -v curl || echo NO) ; net check:"
          su - "$U" -c 'curl -fsS -m 10 -o /dev/null -w "  claude.ai/install.sh HTTP %%{http_code}\n" https://claude.ai/install.sh' 2>&1 | head -2

          UP="$H/.local/bin:$H/.claude/local:$H/bin:$H/.npm-global/bin:/usr/local/bin:/usr/bin:/bin"
          # pick up any found binary's dir too
          for b in $(find "$H" -maxdepth 6 -name claude -o -name codex 2>/dev/null | head -4); do UP="$(dirname "$b"):$UP"; done
          echo "--- ensure CLIs for $U (PATH=$UP) ---"
          su - "$U" -c "PATH=$UP command -v claude" >/dev/null 2>&1 || {
            echo "installing claude CLI for $U…"
            su - "$U" -c 'curl -fsSL https://claude.ai/install.sh | bash 2>&1' | tail -4
          }
          su - "$U" -c "PATH=$UP command -v codex" >/dev/null 2>&1 || {
            echo "installing codex CLI for $U…"
            su - "$U" -c 'curl -fsSL https://chatgpt.com/codex/install.sh | bash 2>&1' | tail -4 \
              || su - "$U" -c 'npm install -g @openai/codex 2>&1' | tail -4
          }
          UP="$H/.local/bin:$H/.claude/local:$H/bin:$H/.npm-global/bin:$UP"

          echo "--- smoke-test claude as $U ---"
          if su - "$U" -c "PATH=$UP command -v claude" >/dev/null 2>&1; then
            OUT="$(timeout 90 su - "$U" -c "PATH=$UP claude --print --dangerously-skip-permissions 'Reply with exactly the token: CRED_OK' 2>&1")"
            echo "claude says: $(echo "$OUT" | head -3)"
            echo "$OUT" | grep -q CRED_OK && echo "RESULT claude: PASS (authenticated on a node that never logged in)" || echo "RESULT claude: FAIL/UNCLEAR"
          else
            echo "RESULT claude: SKIP (claude CLI still not found)"
          fi

          echo "--- smoke-test codex as $U ---"
          if su - "$U" -c "PATH=$UP command -v codex" >/dev/null 2>&1; then
            OUT="$(timeout 120 su - "$U" -c "PATH=$UP codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check 'Reply with exactly the token: CODEX_OK' 2>&1")"
            echo "$OUT" | tail -5
            echo "$OUT" | grep -q CODEX_OK && echo "RESULT codex: PASS" || echo "RESULT codex: FAIL/UNCLEAR"
          else
            echo "RESULT codex: SKIP (codex CLI still not found)"
          fi
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
