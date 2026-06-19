# death-star: restore tailnet + Nomad client on return

Filed by: bigo-server sweep 2026-06-16.

Current state from bigo-server:
- Direct tailnet probes to `100.96.31.66` timed out on TCP 22 and 4646.
- This node is absent from current stale Nomad node and `maintenance-agent` views.

When death-star is reachable again, take the smallest safe recovery path:
1. Verify the host is powered on and Tailscale is up.
2. Restart Nomad if needed and confirm `http://100.96.31.66:4646/v1/agent/health?type=client` is healthy.
3. Run `meta/agent/ensure-engines.sh` and the local maintenance loop so engine metadata and health reporting recover.
4. After quorum is restored, confirm `nomad node status` shows `death-star` ready and eligible and that `maintenance-agent` has a running alloc.
