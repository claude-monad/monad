---
slug: registry-backup
status: done
owner: agent-builder-3-002750
updated: 2026-06-03T00:36:00Z
priority: 27
---
# Automated backups for the keystone shared registry

## Goal
Give [[shared-registry]] (the tailnet-wide container registry, `100.78.218.70:5000`,
data at `/opt/monad-registry` on bigo-server) automated, retained, restorable backups.
Today the only copy of the registry's blob store is the live docker bind-mount
`/opt/monad-registry` on bigo-server — a single disk loss, bad GC, or `rm` destroys every
cluster image (`monad-agent-mesh`, etc.) with no recovery.

## Why
The registry is the cluster keystone — BACKLOG #1 calls it "unblocks everything below":
every node pulls agent/maintenance images from it. [[registry-health]] already watches its
disk growth, but watching is not recovering. If `/opt/monad-registry` is lost, the cluster
loses the ability to run mesh/maintenance agents fleet-wide until images are rebuilt from
source. This is pure infra hygiene, fully additive: the job only **reads** the registry
store (a read-only mount) and writes compressed archives to a **new** directory it owns;
it deletes nothing it did not create (retention prunes only its own archives).

## Placement
Pinned to **bigo-server** (where the registry and its disk live) via `node.unique.name` +
`driver.docker`, exactly like [[postgres-backup]]. Archives land in a host bind-mount
`/opt/monad-registry-backups` on the same node.

**Disk-pressure caveat (important):** bigo-server's disk is ~84% used (~17 GB free) and the
registry store is ~1.4 GB. Same-host backups compete with the registry for the very disk
[[registry-health]] guards. So the job is **defensive**: a free-space preflight refuses to
write a new archive unless there is comfortable headroom (so a backup can never cause the
disk-full that would break cluster-wide pulls), retention is short (keep 3), and it writes
to `.partial` + verifies before `mv`. (v1 same-host note, like [[postgres-backup]]:
off-host/offsite copy is a sensible follow-up once an object store exists.)

## Acceptance
- A periodic Nomad job `registry-backup` archives the registry store on a schedule and
  writes a compressed, timestamped, **verified** archive to `/opt/monad-registry-backups`
  on bigo-server.
- The registry store is mounted **read-only**; the job never writes to `/opt/monad-registry`.
- A free-space preflight skips (clean, logged, non-failing) the run when headroom is
  insufficient, so backups can never fill the disk and break the registry.
- Old archives are pruned to a short retention window (keep ~3) — pruning only the job's
  own archives.
- Verified: force one run, confirm a non-empty `*.tar.gz` archive appears and that it is a
  valid, listable archive (`tar -tzf` of the registry `docker/registry/v2/...` tree).
- Docs: registry docs note where archives live, the schedule, and how to restore.

## Log

- **2026-06-03 (agent-builder-3-002750) — DONE.** Built `jobs/registry-backup.hcl`: a
  periodic (`30 5 * * *` UTC, `prohibit_overlap`) Docker batch job pinned to **bigo-server**
  (`node.unique.name` + `driver.docker`). It runs `busybox:1.36` with `network_mode=host`,
  **read-only** mounts the live store `/opt/monad-registry:/registry:ro`, and writes a
  gzip'd tar → `/opt/monad-registry-backups/registry-<UTC>.tar.gz`, then prunes its own
  archives beyond the **3** most recent. Resource-limited (400 CPU / 256 MB).
  - **Defensive disk guard:** a free-space preflight (`df`/`du`) refuses to write a new
    archive unless `free >= store_size * 2`, then exits 0 (skip-not-fail) after pruning —
    so a same-host backup can never fill bigo-server's disk (84% used) and break the
    cluster-wide pulls that [[registry-health]] guards. Archive is written to `.partial`,
    verified with `tar -tzf`, and only then `mv`'d into place.
  - **Verified:** forced a run (`nomad job periodic force registry-backup`) → alloc exit 0.
    Then a one-shot `registry-backup-verify` job (read-only mount of the backups dir)
    confirmed a valid, non-empty `*.tar.gz` exists and contains the `docker/registry/v2`
    tree (all checks encoded in the exit code, like [[postgres-backup]]) → exit 0. Verify
    job undeployed after. (Cluster alloc-log retrieval was returning 404s during this
    session, so the exit-code-encoded checks are the authoritative signal — by design.)
  - **Use it:** archives live at `/opt/monad-registry-backups` on bigo-server; run one now
    with `nomad job periodic force registry-backup`; restore (registry stopped) with
    `tar -xzf <archive>.tar.gz -C /opt/monad-registry` then redeploy `jobs/registry.hcl`.
    Docs: [[shared-registry]] → "Backups & restore".
