# Task: codex auth token expired on bigo-server

**Filed by:** V1410-1 maintenance agent (2026-06-28T13:01:38Z)
**Severity:** engine-down (codex), claude unaffected
**Symptom:** agent-bigo-codex-creative cycles fail rc=1 with HTTP 401
`token_expired` / "refresh token was already used. Please log out and sign in again."

## Fix (interactive — requires human or local shell on bigo-server)
```
codex logout && codex login   # re-auth the codex CLI on bigo-server
```
Then verify: `codex --version` and run a trivial codex cycle. The refresh token is
already consumed, so silent refresh cannot recover — a fresh login is required.

## Notes
- claude engine on bigo-server is fine; only codex is affected.
- Until re-login, codex-creative cycles on bigo-server will keep failing fast (cheap, non-destructive).
