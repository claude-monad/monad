---
slug: gateway-deploy-deadline
status: blocked
owner: agent-builder-3-031242
updated: 2026-06-03T03:42:00Z
priority: 43
---
# gateway-deploy-deadline: node-chat-gateway deployments false-fail — root cause is claudebox node networking

## Summary (status: blocked — proper fix is owner-domain client config)
`node-chat-gateway` deployments are always marked **failed** (`Alloc Unhealthy … by
healthy_deadline`) even though the service comes up and serves `/health` 200 / `/ask` rc:0. The
recurring cause is **not** a slow first-start (as previously assumed) and **not** the
`healthy_deadline` length. It is a **node-level Nomad networking mismatch on claudebox** that I
cannot fix safely (it requires editing the live client config).

## Root cause (measured)
- The gateway binds the **Tailscale** interface: `CONDUCTOR_BIND="$(tailscale ip -4)"` →
  `100.87.219.108:8201`. Verified: `GET http://100.87.219.108:8201/health` → **200** (~0.1s).
- But claudebox's Nomad client advertises the host's **LAN** IP for the allocated port — the
  `node-chat-gateway-claudebox` service registers `192.168.51.19:8201`, and Nomad's HTTP check
  targets that. Verified `nomad alloc checks`: `Status = failure`, output
  `Get "http://192.168.51.19:8201/health": dial tcp 192.168.51.19:8201: connect: connection
  refused`. The gateway never listens on `192.168.51.19`, so the check **can never pass**, and the
  deployment fails at the deadline regardless of its length.
- claudebox defines **no** named `host_network` (e.g. `tailscale`) and no `network_interface`
  pointing at the Tailscale NIC (checked `nomad node status -verbose` + `cluster/client*.hcl`), so
  there is no in-job way to make the port advertise/check the Tailscale address.

## Wider impact (why this is owner-domain, not a per-service patch)
This is bigger than one check: Nomad **service discovery** for *any* host-networked service on
claudebox returns the unreachable LAN IP `192.168.51.19`. Consumers only work today because they
hardcode the Tailscale IP (dashboard/conductor do). The correct fix is a **client config** change
on claudebox — set the default `network_interface` (or a `host_network "tailscale"` block) to the
Tailscale NIC so Nomad advertises `100.87.219.108`. That is the Nomad client config, which fleet
builders must not touch (PROTOCOL: never touch `cluster/` server/client configs; escalate
cluster-wide/uncertain changes to the conductor/owner).

## What I did NOT do, and why
- A longer `healthy_deadline` (my first attempt) does nothing — the check is permanently refused,
  not slow. **Reverted** (`jobs/node-chat-gateway.hcl` back to committed baseline; no drift).
- Binding the gateway to `0.0.0.0` would let the LAN-IP check pass, but it exposes the Claude
  `/ask` endpoint on the LAN, violating the cluster's Tailscale-only networking principle.
- Removing the broken check would make the deployment go green, but it papers over a node-wide
  discovery defect that the owner should fix properly — escalated instead.

## Mitigation already in place
The gateway is functionally **restored and serving** (I redeployed it under the standing health
mandate after claudebox bounced at 03:15 killed it), and [[conductor-gateway-liveness]] (#42) now
probes the gateway's *Tailscale* `/health` into `fleet/health-summary` (`service:gateway`), so its
real liveness is monitored correctly despite the broken Nomad check. The failed *deployment record*
is cosmetic: no `auto_revert`, so the serving alloc survives.

## Unblock / acceptance (for the owner or a node-config-authorized agent)
- On claudebox, set the Nomad client default `network_interface` to the Tailscale NIC (or add a
  `host_network "tailscale"` and set the gateway port's `host_network = "tailscale"`), restart the
  client; then `monad deploy jobs/node-chat-gateway.hcl` → deployment reaches **successful** and
  the service registers `100.87.219.108:8201`.

## Log
- 2026-06-03 (agent-builder-3-031242) opened as a `healthy_deadline` tweak, then **measured the
  real root cause** (Nomad advertises claudebox LAN IP; Tailscale-bound service → check always refused).
  Reverted the misdiagnosed change, set **blocked**, escalated to conductor/owner via fleet event +
  mesh. Gateway itself is restored + #42-monitored; only the deployment-health record and
  claudebox service-discovery remain wrong, both fixable only by the owner-domain client config.
