# webhook/ — GitHub events kick off the cluster

The "push" half of the hybrid trigger ([[../PROTOCOL.md]] → Session model). GitHub events on
the repos flow to a public Tailscale Funnel endpoint on `claudebox`, a receiver applies
cross-source routing rules, and each match **emits a durable task and dispatches a job now**.
The dispatcher pull-loop + task queue are the safety net if a delivery is missed.

```
GitHub (push / PR)
   → https://claudebox.<tailnet>.ts.net/hook        (Tailscale Funnel, public, port 443)
       → 127.0.0.1:8089  server.py                  (HMAC-verified receiver)
           → rules.py  (logic across the sources)
               → task.sh emit  (durable)  +  nomad job dispatch  (immediate kick-off)
```

## Pieces
- `rules.py` — the routing table + a pure matcher (unit-testable). Edit this to change which
  source events kick off which work. Example: a push to `math:05-knowledge/hypotheses/*` →
  dispatch `math-formalizer` against `math-lean`.
- `server.py` — receiver. **Verifies `X-Hub-Signature-256` (HMAC-SHA256)**, de-dupes delivery
  ids, accepts only repos in the rule table, dispatches only fixed job names. Never executes
  payload text. `DRY_RUN=1` logs without acting.
- `funnel.sh` — runs the receiver and publishes the Funnel (`start|keepalive|stop|status|url`).
- `setup-webhooks.sh` — registers the GitHub webhooks on the repos we control.

## Security
Public endpoint that can dispatch jobs, so: mandatory HMAC signature check (shared secret in
`~/nomad/webhook.secret`, gitignored), repo allowlist (only repos named in `rules.py`), event
allowlist, fixed actions (a known job + bounded scope string — payload text is never run), and
delivery-id dedup. Funnel only exposes `/hook` and `/health`.

## Bring it up (one-time)
1. **Grant funnel rights** (one-time, needs sudo on claudebox — Funnel won't run as a plain
   user otherwise):
   ```bash
   sudo tailscale set --operator=$USER
   ```
2. **Start it:**
   ```bash
   ~/monad/meta/coordination/webhook/funnel.sh start      # prints the public /hook URL
   ```
   Keep it alive via cron:
   ```bash
   (crontab -l 2>/dev/null; echo "*/5 * * * * $HOME/monad/meta/coordination/webhook/funnel.sh keepalive >> $HOME/nomad/webhook.log 2>&1") | crontab -
   ```
3. **Register webhooks** (repos we control — monad, math-lean, math fork):
   ```bash
   ~/monad/meta/coordination/webhook/setup-webhooks.sh
   ```
4. **Upstream `eliottcassidy2000/math`** (owner-only — we lack admin): add a webhook with the
   same URL, content-type `json`, the shared secret, events `push` + `pull_request`. This is the
   most important source (the research repo), so it's worth adding.

Until step 1 is done the receiver runs fine on localhost but is not reachable from GitHub.
Test safely first with `DRY_RUN=1 funnel.sh start` and a signed `curl` to the printed URL.
