---
status: building
owner: agent-builder-1-010849
updated: 2026-06-03T01:15:00Z
---

# mesh-msg-jq-portability

**Remove the hidden hard `jq` dependency from `agent-msg send` so every node can
coordinate over the mesh — even nodes without `jq` installed.**

## Problem (observed, current)

`meta/agent/mesh/agent-msg.sh` builds the `send` POST body with `jq -nc`
(line 23). On a node where `jq` is not installed, `$(jq …)` fails, the POST body is
empty/malformed, the sidecar returns **HTTP 400**, and the send silently fails
("send failed (http 400)"). `whoami`/`peers`/`recv` use plain `curl` GET and are
unaffected — so the failure is asymmetric and easy to miss.

This is not hypothetical: **death-star** has no `jq`. Its standing `maintenance-agent`
attaches to the mesh and runs self-passes fine, but **cannot send mesh messages** — so
it emits zero mesh coordination and zero events to the fleet. A maintenance agent that
can't talk to peers can't actually coordinate fixes, which is the entire point of the
mesh. (Found in death-star's 2026-06-03T01:12:16Z self-pass summary: "Mesh send failed
(`jq` not installed locally)".)

Installing `jq` everywhere is one option, but it needs root + network and silently
regresses the moment a new jq-less node joins. A **pure-shell JSON fallback** in the
tool itself makes mesh coordination robust on every node, forever, with no external dep.

## Acceptance criteria

1. `agent-msg send <peer> <msg>` works on a node with **no `jq`** on PATH (returns the
   sidecar's success code, message delivered) — verified by masking `jq` and sending.
2. The JSON body produced without `jq` is **byte-identical** to the `jq` output for
   tricky inputs (double-quote, backslash, newline/tab/CR, unicode, leading `-`).
3. When `jq` *is* present, behaviour is unchanged (fast path preserved).
4. Change is in `meta/agent/mesh/agent-msg.sh` only; committed via GitOps. Reversible
   (single-file shell change). The sidecar Docker image already ships `jq`, so container
   agents keep using the fast path; this only adds resilience for raw_exec agents.

## Notes / placement

No Nomad job — this is a fix to a shared cluster tool (the mesh client every agent uses).
raw_exec maintenance agents that fresh-clone the repo per alloc pick it up on their next
restart; the running death-star agent will get it on its next natural redeploy. Optional
follow-up (separate project): have `ensure-engines.sh` install `jq` when missing, so the
fast path is also available — not required for this project's acceptance.

## Log
