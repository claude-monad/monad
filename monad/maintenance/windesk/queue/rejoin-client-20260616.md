# windesk: restore tailnet + Nomad client on return

Filed by: bigo-server sweep 2026-06-16.

Current state from bigo-server:
- Direct tailnet probes to `100.94.210.54` timed out on TCP 22 and 4646.
- `V1410-1` is leaderless, so this node is missing from current stale Nomad node and `maintenance-agent` views.

When windesk is reachable again, take the smallest safe recovery path:
1. Verify the machine is powered on and Tailscale is authenticated (`tailscale up` if needed).
2. Restart the Nomad client and confirm `http://100.94.210.54:4646/v1/agent/health?type=client` is healthy.
3. Run the Windows equivalent of the maintenance loop (`node-doctor` scheduled task) and confirm the repo is current.
4. Re-run engine setup if needed so the node advertises capability again.
5. After quorum is restored, confirm `nomad node status` shows `windesk` ready and eligible.
