#!/usr/bin/env bash
# setup-webhooks.sh — register GitHub webhooks on the repos we control, pointed at the
# Tailscale Funnel endpoint, with the shared HMAC secret. Run ONCE the funnel is live.
# Idempotent: deletes any prior hook to the same URL first.
#
# Repos we have admin on: eliott-monad/monad, eliott-monad/math-lean, claude-monad/math.
# The UPSTREAM eliottcassidy2000/math needs its owner to add the same webhook (we lack
# admin there) — see README.
set -euo pipefail

SECRET="$(cat "${WEBHOOK_SECRET_FILE:-$HOME/nomad/webhook.secret}")"
url_default() { tailscale status --json 2>/dev/null | python3 -c "import sys,json;print('https://'+json.load(sys.stdin)['Self']['DNSName'].rstrip('.')+'/hook')"; }
URL="${WEBHOOK_URL:-$(url_default)}"

python3 - "$URL" "$SECRET" <<'PY'
import json, subprocess, sys, tempfile, os
url, secret = sys.argv[1], sys.argv[2]
body = {"name": "web", "active": True, "events": ["push", "pull_request"],
        "config": {"url": url, "content_type": "json", "secret": secret, "insecure_ssl": "0"}}
for repo in ["eliott-monad/monad", "eliott-monad/math-lean", "claude-monad/math"]:
    ex = subprocess.run(["gh", "api", f"repos/{repo}/hooks", "--jq",
                         f'.[] | select(.config.url=="{url}") | .id'],
                        capture_output=True, text=True)
    for hid in ex.stdout.split():
        subprocess.run(["gh", "api", "-X", "DELETE", f"repos/{repo}/hooks/{hid}"], capture_output=True)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(body, f); tmp = f.name
    r = subprocess.run(["gh", "api", "-X", "POST", f"repos/{repo}/hooks", "--input", tmp],
                       capture_output=True, text=True); os.unlink(tmp)
    if r.returncode == 0:
        print(f"OK  {repo}  hook id={json.loads(r.stdout)['id']}  -> {url}")
    else:
        print(f"ERR {repo}: {r.stderr.strip()[:160]}")
PY

echo "Add the same webhook on eliottcassidy2000/math (owner-only):"
echo "  URL=$URL  content-type=json  secret=<shared>  events: push, pull_request"
