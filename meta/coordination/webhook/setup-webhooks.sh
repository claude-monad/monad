#!/usr/bin/env bash
# setup-webhooks.sh — register GitHub webhooks on the repos we control, pointed at the
# Tailscale Funnel endpoint, with the shared HMAC secret. Run ONCE the funnel is live
# (funnel.sh start succeeded). Idempotent: updates an existing hook with the same URL.
#
# Repos we have admin on: claude-monad/monad, claude-monad/math-lean, claude-monad/math.
# The UPSTREAM eliottcassidy2000/math needs its owner to add the same webhook (we lack
# admin there) — see README.
set -euo pipefail

SECRET="$(cat "${WEBHOOK_SECRET_FILE:-$HOME/nomad/webhook.secret}")"
url_default() { tailscale status --json 2>/dev/null | python3 -c "import sys,json;print('https://'+json.load(sys.stdin)['Self']['DNSName'].rstrip('.')+'/hook')"; }
URL="${WEBHOOK_URL:-$(url_default)}"

REPOS=("claude-monad/monad" "claude-monad/math-lean" "claude-monad/math")
EVENTS='["push","pull_request"]'

for repo in "${REPOS[@]}"; do
  # remove any prior hook to the same URL (idempotent)
  existing=$(gh api "repos/$repo/hooks" --jq ".[] | select(.config.url==\"$URL\") | .id" 2>/dev/null || true)
  for id in $existing; do gh api -X DELETE "repos/$repo/hooks/$id" >/dev/null 2>&1 || true; done
  gh api -X POST "repos/$repo/hooks" \
    -f name=web -F active=true \
    -f "events[]=push" -f "events[]=pull_request" \
    -f config[url]="$URL" -f config[content_type]=json \
    -f config[secret]="$SECRET" -f config[insecure_ssl]=0 \
    --jq '"\(.config.url)  hook id=\(.id)  on '"$repo"'"' 2>&1 | tail -1
done
echo "done. Add the same webhook on eliottcassidy2000/math (owner-only):"
echo "  URL=$URL  content-type=json  secret=<the shared secret>  events: push, pull_request"
