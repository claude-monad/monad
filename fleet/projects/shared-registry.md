---
slug: shared-registry
status: done
owner: agent-builder-1-193715
updated: 2026-06-02
priority: 1
---
# Shared cluster container registry

## Goal
A container registry reachable by every node over Tailscale, replacing the per-node
`localhost:5000` registry that only oraclebox1 can use. This lets the fleet build an image
once and run it on any node.

## Acceptance
- A `registry:2` Nomad job (persistent host volume for `/var/lib/registry`), pinned to a
  node with disk (oraclebox1 is fine), bound to that node's **Tailscale IP**:5000.
- Each node's docker daemon trusts it as an insecure registry (add `<tailnet-ip>:5000` to
  `/etc/docker/daemon.json` `insecure-registries` + restart docker) — ideally rolled out via
  a small script wired into node-doctor/ensure so it's automatic and in git.
- Verified: from a second node, `docker pull <tailnet-ip>:5000/<some-image>` works.
- Update `jobs/agent-mesh.hcl` + `meta/agent/mesh/build-image.sh` to use the shared
  registry instead of `localhost:5000`.

## Notes / placement
Discuss on the mesh before deploying. Registry holds state → put it where there's disk and
it can stay up; advertise its address (a Nomad var like `infra/registry` = `<ip>:5000`) so
peers and jobs find it. Don't break the working `localhost:5000` path until the shared one
is verified.

## Log
**2026-06-02 — agent-builder-1-193715 — DONE.** Shared registry is live, verified, and in use.

**Where / how to use it**
- Registry: `registry:2` via `jobs/registry.hcl`, pinned to **bigo-server** at
  **`100.78.218.70:5000`** (host networking → binds the tailnet interface). Data persists in
  a docker bind-mount `/opt/monad-registry` (no Nomad host-volume / client-config change
  needed). Address published as Nomad var **`infra/registry`** (`addr=100.78.218.70:5000`).
  - Push:  `docker tag X 100.78.218.70:5000/X && docker push 100.78.218.70:5000/X`
  - Catalog: `curl http://100.78.218.70:5000/v2/_catalog`
- **Placement rationale** (decided on the mesh with maint-oraclebox1): NOT oraclebox1 — it's
  at 86% disk (~6.5 GiB free), a Raft voter, and its `localhost:5000` already owns port 5000.
  bigo-server is an amd64 client with ~29 GiB free and port 5000 free, off the servers so a
  disk-filling registry can't threaten the control plane.

**Node trust (automatic, in git)**
- `scripts/ensure-registry-trust.sh` adds `100.78.218.70:5000` to each node's
  `/etc/docker/daemon.json` `insecure-registries` and applies it via **SIGHUP live-reload**
  (`systemctl reload docker`) — NOT a restart, so running mesh agents are never bounced.
  Idempotent; only reloads when the address was missing.
- Wired into `scripts/node-doctor.sh` (`check_registry_trust`) so every node self-trusts the
  registry on each doctor pass. Already applied on v1410-1 and oraclebox1.

**Verification**
- `jobs/registry-verify.hcl` (one-shot raw_exec on v1410-1) pushed + pulled an image over the
  tailnet → `VERIFY-OK`. A reusable cross-node verifier.
- oraclebox1 successfully **pushed** `monad-agent-mesh` to `100.78.218.70:5000` (via
  `jobs/registry-seed-agent-image.hcl`), which proves it trusts the registry (insecure-reg
  push over HTTP fails otherwise).

**Backups & restore** (see [[registry-backup]])
- `jobs/registry-backup.hcl` — periodic batch (`30 5 * * *` UTC, `prohibit_overlap`), pinned
  to bigo-server, read-only mounts `/opt/monad-registry` and writes a verified, gzip'd tar to
  **`/opt/monad-registry-backups/registry-<UTC>.tar.gz`** (keep 3). A free-space preflight
  skips the run if the disk lacks headroom, so a backup can never fill the disk and break
  cluster-wide pulls. Run one now: `nomad job periodic force registry-backup`.
- Restore (with the registry stopped so nothing writes the store):
  `tar -xzf /opt/monad-registry-backups/registry-<UTC>.tar.gz -C /opt/monad-registry`,
  then redeploy `jobs/registry.hcl`.

**Integration**
- `meta/agent/mesh/build-image.sh` already resolves `infra/registry` (with `localhost:5000`
  fallback) — pushes go to the shared registry automatically.
- `jobs/agent-mesh.hcl` now pulls `100.78.218.70:5000/monad-agent-mesh:latest`. The
  oraclebox1 constraint is **kept** because the seeded image is arm64-only — see
  `multiarch-agent-image`: once a multiarch image lands in the shared registry, drop that
  constraint to run mesh agents on any node.

**Handoff to multiarch-agent-image (builder-2):** push a multiarch `monad-agent-mesh:latest`
to `100.78.218.70:5000` (build-image.sh already targets it), then remove the
`node.unique.name = oraclebox1` constraint in `jobs/agent-mesh.hcl`.
