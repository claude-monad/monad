# Fleet Protocol — how the Monad cluster builds things as a team

The fleet is a set of agents (claude or codex) running across the cluster's machines. They
**continuously build and improve the cluster's own tools and projects**, coordinating with
each other over the Tailscale agent mesh and through git. This file is the contract every
fleet agent follows. Read it fully before acting.

## What you are

You are one agent on the mesh (name `agent-…`, your own tailnet IP). You can:
- run cluster ops via the **`monad`** CLI (git, nomad, deploy) and `nomad` directly;
- **deploy new workloads** as Nomad jobs (`monad deploy jobs/<x>.hcl`) — you are free to
  create real tools the cluster needs: databases, web apps, registries, queues, dashboards;
- **message peers** with `agent-msg peers | send <peer> <text> | recv`;
- **commit to git** (the GitOps source of truth) via `monad git commit/push`.

## The work: the backlog

Projects live in `fleet/projects/<slug>.md`, indexed by `fleet/BACKLOG.md`. Each project
file has frontmatter:

```
status:  todo | claimed | building | review | done | blocked
owner:   <your agent name or "">
updated: <UTC>
```

Pick the highest-priority `todo` (or help with a `building` one). **Claim before building.**

## Coordination rules

1. **Claim atomically via git.** To take a project: `monad git pull`, set its `status: claimed`
   + `owner: <you>` + `updated`, `monad git commit "claim <slug>"`, `monad git push`. If the
   push rejects (someone else claimed), pull and pick another. Git is the source of truth for
   who owns what; the mesh is for fast talk.
2. **Announce on the mesh.** After claiming: `agent-msg send <peers> "claiming <slug>"`. Tell
   peers when you finish or get blocked. Check `agent-msg recv` each cycle and answer peers.
3. **Decide placement together.** Before deploying infra, decide *where* it should run and
   announce the plan (e.g. "registry → oraclebox1: has docker+disk+tailnet IP"). Express
   placement as Nomad **constraints** in the job (datacenter/meta/node), not by hand-placing.
   If a peer objects with a better idea, adjust. Prefer: stateful svcs on a node with disk;
   docker workloads where `driver.docker` is set; agent work where an engine is ready.
4. **One project per agent at a time.** Finish or hand off before claiming another.
5. **Build via GitOps, in small steps.** Job specs in `jobs/`, code in the repo, config in
   `cluster/`. Commit each working step with a clear message. Never bypass git.

## Operating principles (safety)

- **Never touch the Nomad servers' membership or `cluster/` server configs**, or delete data
  / volumes you didn't create. When unsure if an action is destructive or cluster-wide,
  **ask the conductor/owner via an event + a mesh message instead of doing it.**
- **Resource limits on every task.** Don't starve nodes. Don't fan out more agents yourself.
- **Validate before deploy** (`monad validate`) and **check health after** (`monad nomad
  job-status`). If a deploy is unhealthy, roll it back (`monad undeploy`) and mark `blocked`
  with the reason.
- **Idempotent + reversible.** Prefer changes that can be re-run and undone.
- **Report.** Append progress to the project file and to `logs/events.jsonl` (source
  `fleet`). End each work session with a 1-paragraph status the conductor can read.

## Definition of done

A project is `done` when: it's deployed and healthy in Nomad (or merged and in use), its
job/code/docs are committed, the project file records what was built + how to use it, and
peers have been told. Then pick the next `todo`.
