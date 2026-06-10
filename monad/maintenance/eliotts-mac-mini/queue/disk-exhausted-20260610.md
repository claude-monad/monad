# Task: eliotts-mac-mini disk exhausted — maintenance-agent cannot place
Detected 2026-06-10 by V1410-1 health sweep.
`nomad job status maintenance-agent` shows the agent task-group QUEUED on this node
with placement failure: "Resources exhausted / Dimension disk exhausted on 1 nodes".
No running maintenance-agent alloc here until disk frees up.

Fix on-node (smallest first):
1) Check usage: `df -h /` and `du -sh ~/.cache/* /tmp/* 2>/dev/null | sort -h | tail`.
2) Free obvious junk: prune old Nomad alloc dirs (`nomad system gc`), clear stale
   `~/Library/Caches`, `/tmp`, old build/log artifacts. `docker system prune -f` if docker idle.
3) Confirm the node's reserved/available disk clears the maintenance-agent task-group
   requirement, then it will auto-place (no redeploy needed).
4) Verify: `nomad job status maintenance-agent` shows a running alloc on eliotts-mac-mini,
   and run `meta/agent/ensure-engines.sh`.
Quorum is SAFE (V1410-1 leader + claudebox voter); this is client-disk only, not urgent.
