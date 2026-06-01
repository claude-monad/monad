# tasks/ — the git-backed task queue

One JSON file per task (`t-NNNN.json`), created by `../task.sh`. Emitting a task is a commit;
`frontier.py` surfaces open tasks to the dispatcher. See `../PROTOCOL.md` → "The task queue".
Small sessions claim one task, do it, and emit follow-ups instead of doing everything inline.
