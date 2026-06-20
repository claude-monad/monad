# claudebox: restore Nomad quorum

Filed by: eliotts-mac-mini sweep 2026-06-20T14:46:36Z.

Current control-plane state from eliotts-mac-mini:

- `nomad server members` shows only `V1410-1.global` alive and `Leader=false`; the command returns `500 No cluster leader`.
- `nomad node status` and `nomad job status maintenance-agent` both fail with `500 No cluster leader`, so roster readiness and maintenance-agent coverage cannot be verified until quorum returns.
- `tailscale ping` succeeds for `bigo-server`; `claudebox` (`100.87.219.108`), `oraclebox1` (`100.125.210.126`), and `death-star` (`100.96.31.66`) give no reply from eliotts-mac-mini.
- eliotts-mac-mini local self-check completed; `meta/agent/ensure-engines.sh` advertises `has_claude=true`, `has_codex=true`, `agent_engines=claude,codex`.

Smallest safe recovery:

1. Restore claudebox power/Tailscale out-of-band.
2. On claudebox, run `~/monad/scripts/claudebox-server.sh keepalive` or `~/monad/scripts/claudebox-server.sh start`.
3. After a leader returns, verify `nomad server members`, `nomad node status`, and `nomad job status maintenance-agent`.

Avoid single-voter Raft surgery unless an operator explicitly approves it.
