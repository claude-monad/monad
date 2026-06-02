---
slug: shared-registry
status: todo
owner: ""
updated: ""
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
(append progress here)
