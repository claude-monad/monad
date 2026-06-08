# oraclebox1: restore as Nomad server voter
Detected by V1410-1 maint sweep 2026-06-08: host was offline on Tailscale (last seen ~22h)
and its Nomad server showed `failed` in `nomad server members`; quorum held at 2/3 (V1410-1
leader + claudebox). On return:
1. `sudo tailscale up` — confirm mesh reachable.
2. Restart Nomad: `sudo systemctl restart nomad` (or relaunch agent).
3. Verify rejoin: `nomad server members` shows oraclebox1 `alive` → back to 3 voters.
4. Run `meta/agent/ensure-engines.sh` to re-advertise engines.
