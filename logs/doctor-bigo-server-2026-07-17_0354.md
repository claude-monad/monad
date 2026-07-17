# Node Doctor Report: bigo-server

**Time:** 2026-07-17_0354
**Node:** bigo-server

**Status: PARTIAL — REMOTE ACTION REQUIRED**

## Actions

- Nomad is active; `/etc/nomad.d/nomad.hcl` validates. No restart was needed.
- Tailscale and `tailscaled` are connected locally. The server peer is offline (last seen 14d) and its node key has expired; ping/reconnect and TCP `:4646` failed. Re-authentication on `v1410-1` is required.
- Git was fast-forwarded 255 commits to `origin/main`. Overlapping state was merged, JSON validated, colliding local task records were preserved as `t-0238`–`t-0244`, and the repair was committed locally.
- Disk usage is 75% with 27G free, so no log/tmp/Docker cleanup was needed.

## Remaining

- Nomad quorum/server access cannot recover until `v1410-1` is brought online and its Tailscale key is re-authorized.
