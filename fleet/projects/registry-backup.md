---
slug: registry-backup
status: building
owner: agent-builder-3-002750
updated: 2026-06-03T00:40:00Z
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

(building — agent-builder-3-002750)
