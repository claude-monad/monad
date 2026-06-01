# meta/dispatch — containerized autonomous Claude sessions

Run Claude research sessions in **isolated containers**, chosen and deduplicated by
the frontier **dispatcher**. This replaces ad-hoc remote-control launches (which
shared one working tree and collided) with automatic, isolated, claim-deduped
sessions.

Each container clones the repo fresh, so concurrent sessions never touch the same
working tree. Auth comes from the host at runtime: the host's `~/.claude` OAuth is
mounted, and a GitHub token (`gh auth token`) is injected for `git push`.

## Two job types

| Type | Prompt | Warm-up | Timeout | When |
|------|--------|---------|---------|------|
| **explorer** (default, bread & butter) | `scripts/prompts/explorer.md` | full | 60 min | deep, long-lived sessions that ponder and hunt hidden connections; the continuous background loop |
| **targeted** (lightweight) | `scripts/prompts/targeted.md` | none (reads only MISTAKES.md) | 20 min | fast, surgical progress on ONE specific question |

Pick with `--mode {explorer,targeted}` on the dispatcher, `MONAD_MODE`/arg on
`auto-dispatch.sh`, or fire a targeted session at a literal question with
`ask.sh "<question>"`.

## Pieces

| File | What |
|------|------|
| `Dockerfile` / `entrypoint.sh` | the `monad-claude-session` image: git + python + Claude CLI, runs as non-root `ubuntu` (Claude refuses `--dangerously-skip-permissions` as root) |
| `build-image.sh` | build the image |
| `auth-check.sh` | verify containerized Claude auth works (prints `AUTHENTICATED`) |
| `run-container-session.sh` | launch ONE session: `run-container-session.sh <machine-id> <prompt|@file> [--detach]` |
| `auto-dispatch.sh` | cron entry: keep one container running on this host, picked by the dispatcher |
| `../coordination/dispatcher.py --exec container` | the dispatcher’s container backend |

## One-time setup (per host)

```bash
# host must be logged into Claude (claude) and GitHub (gh auth login)
meta/dispatch/build-image.sh         # build the image (sudo docker)
meta/dispatch/auth-check.sh          # expect: AUTHENTICATED
```

## Run a single session by hand

```bash
meta/dispatch/run-container-session.sh test-1 "Do a short compute task and close out."
```

## Autonomous (the goal)

`auto-dispatch.sh` asks the dispatcher for the top frontier item for **this host's
account** (detected from `/etc/nomad.d/nomad.hcl` `meta.claude_account`, else
`$MONAD_ACCOUNT`, else `pro`), claims it (cluster-memory dedup, shared with the
Nomad path), and launches one container. A guard prevents stacking a second
session on the same account's credentials. Enable it on a cron:

```cron
*/15 * * * * /home/ubuntu/monad/meta/dispatch/auto-dispatch.sh >> /tmp/auto-dispatch.log 2>&1
```

Dry-run first (launches nothing):

```bash
python3 meta/coordination/dispatcher.py --exec container --account pro
```

## Design notes / limits

- **One container per account at a time.** The account credentials and rate limit
  are shared; concurrency on one account would race on OAuth refresh. Scale by
  adding hosts/accounts, not parallel containers per account.
- **Credentials** are mounted read-write so the container's token refresh persists
  back to the host (keeps the host token fresh). The container also writes some
  session history into `~/.claude/projects/-work` — harmless.
- **Heavy warm-up.** The math repo's `CLAUDE.md` mandates a long startup (read 6
  files, process the inbox, scour the repo). A dispatched session therefore takes
  several minutes before producing — fine for deep work, but if you want quick
  turnaround add a lighter dispatched-session prompt that skips the full warm-up.
- **Dedup vs the manual path.** Sessions launched this way claim their frontier
  item, so they won't duplicate each other. Manual `claude` runs in `~/math` still
  bypass the claim — prefer dispatch (or a worktree, see the math repo's
  `CONCURRENT-SESSIONS.md`) over manual runs in the shared tree.
