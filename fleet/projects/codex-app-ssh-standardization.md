---
slug: codex-app-ssh-standardization
status: todo
owner: null
updated: 2026-06-04T20:55:01Z
priority: 1
---

# codex-app-ssh-standardization

## Owner Request
Allow SSH session integration from the GPT mobile and desktop apps so the owner can talk to the
containerized math researchers through a standardized, elegant route on every cluster node.

The owner verified `oraclebox1` from the iOS app on port 22 using its reachable address and a
username/password, but the success path was unclear because Tailscale was expected to own port 22.
Investigate that success and build a cluster-wide access model from it.

## Findings So Far

Checked from the local workstation on 2026-06-04:

- `100.125.210.126:22` is open and presents `SSH-2.0-Tailscale`.
- `100.125.210.126:2222` is open and presents `SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.16`.
- A batch SSH probe to port 22 as `oralcle` reaches Tailscale SSH and returns:
  `tailscale: failed to look up local user "oralcle"`.
- A batch SSH probe to port 2222 as `autocodex` reaches the dedicated OpenSSH listener and offers
  `publickey,keyboard-interactive`; local workstation key was not authorized.

Interpretation: the port-22 success was through Tailscale SSH, not the Nomad `codex-ssh` listener.
The dedicated app-facing listener already exists on port 2222 for Linux nodes that can host it.

## Desired State

- A single documented SSH target model for GPT mobile/desktop app sessions.
- Prefer key-based auth and standard usernames over passwords.
- Keep Tailscale SSH on port 22 for node administration; use a separate app-facing port such as
  2222 for Codex/app sessions unless the owner explicitly chooses otherwise.
- The login shell or first-run experience should make it easy to attach to the math researcher
  pool, not drop the owner into a mystery host shell.
- Every eligible Linux node should either serve the standardized app SSH door or publish why it is
  not hostable.

## Acceptance

- Confirm live `codex-ssh` status across all Linux nodes and record which nodes serve `:2222`.
- Store the GPT app SSH public key in `secret/codex-ssh` or document the exact owner action needed
  to do so.
- Standardize the user, port, and auth method. Current candidate: `autocodex@<node>:2222` with
  key auth only.
- Add an owner-facing roster command or doc that lists app SSH endpoints and researcher attach
  targets.
- Wire the app SSH login to the containerized math researcher pool where possible, for example via
  a menu, tmux attach commands, or a small `researcherctl` helper.
- Do not expose password SSH broadly as the steady-state path.

## Log

- 2026-06-04 — Owner requested mobile/desktop GPT app SSH integration for all cluster nodes and
  asked the fleet to investigate why `oraclebox1:22` worked. Initial probe shows port 22 is
  Tailscale SSH and port 2222 is the dedicated `codex-ssh` OpenSSH listener.
