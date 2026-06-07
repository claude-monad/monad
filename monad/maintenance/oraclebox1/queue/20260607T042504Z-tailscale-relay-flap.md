# Task: investigate Nomad client heartbeat flapping on oraclebox1

Filed by: V1410-1 maintenance sweep 2026-06-06.

Symptom: oraclebox1 Nomad *client* node oscillates down<->ready ("Node heartbeat
missed" / "reregistered" every few minutes). Server/voter role is alive and quorum
is healthy (3 voters). Tailscale shows oraclebox1 on a **relay path ("ord"), no
direct connection** — likely root cause of heartbeat loss and maintenance-agent
alloc churn.

Smallest fixes (least disruptive first):
1. `tailscale ping oraclebox1`-style check from oraclebox1 to v1410-1; try
   `tailscale set --advertise-... ` / restart tailscaled to re-establish a DIRECT path.
2. If client agent is wedged, restart only the Nomad *client* (not the server).
3. Re-run meta/agent/ensure-engines.sh once stable so engines stay advertised.

Do NOT wipe data, force-push, or restart the server (would risk quorum).
