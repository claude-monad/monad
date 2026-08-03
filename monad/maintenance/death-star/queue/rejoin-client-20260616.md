# death-star: restore tailnet + Nomad client on return

Filed by: bigo-server sweep 2026-06-16.

Update 2026-08-03T08:00:56Z from claudebox: all five authoritative Tailscale probes still
timed out and TCP `:4646` is closed. This remains on-box power/Tailscale/Nomad recovery work;
the cluster cannot reach the host to restart it remotely.

Current state from bigo-server:
- Direct tailnet probes to `100.96.31.66` timed out on TCP 22 and 4646.
- This node is absent from current stale Nomad node and `maintenance-agent` views.

When death-star is reachable again, take the smallest safe recovery path:
1. Verify the host is powered on and Tailscale is up.
2. Restart Nomad if needed and confirm `http://100.96.31.66:4646/v1/agent/health?type=client` is healthy.
3. Run `meta/agent/ensure-engines.sh` and the local maintenance loop so engine metadata and health reporting recover.
4. After quorum is restored, confirm `nomad node status` shows `death-star` ready and eligible and that `maintenance-agent` has a running alloc.

Update 2026-08-03T08:44:23Z from claudebox: the host again failed all five Tailscale
probes and a 40-second Nomad API probe. Recovery remains on-box power/Tailscale/Nomad work;
there is no remote restart path from the cluster.
