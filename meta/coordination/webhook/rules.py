#!/usr/bin/env python3
"""rules.py — the routing logic across the sources.

Given a normalized GitHub event (repo, event, action, changed paths), decide which
cluster actions to kick off. Each matched rule produces an Action that the receiver
turns into BOTH a durable task (task.sh emit) AND an immediate Nomad dispatch (the
hybrid: push now, the task queue + dispatcher pull-loop are the safety net).

Rules are pure data + a pure matcher, so they are unit-testable with no network.
Keep actions FIXED (a known job + a bounded scope string); never execute payload text.
"""
from __future__ import annotations
from dataclasses import dataclass
from fnmatch import fnmatch


@dataclass(frozen=True)
class Action:
    task_type: str      # math | compute | formalize | review | merge | push
    repo: str           # where the follow-up work happens
    job: str | None     # Nomad job to dispatch immediately (None = queue only)
    scope: str          # one-line human description (bounded, no raw payload exec)


@dataclass(frozen=True)
class Rule:
    repo: str                 # source repo full_name this rule listens to
    event: str                # github event: push | pull_request | ...
    action: str | None        # for pull_request: opened|closed|... ; None = any
    path_glob: str | None     # for push: only fire if a changed path matches; None = any
    make: object              # callable(ctx) -> Action

    def matches(self, repo, event, action, paths) -> bool:
        if self.repo != repo or self.event != event:
            return False
        if self.action is not None and self.action != action:
            return False
        if self.path_glob is not None:
            return any(fnmatch(p, self.path_glob) for p in (paths or []))
        return True


# ── the cross-source rule table ──────────────────────────────────────────────
# "logic across the sources": events in one repo kick off work routed to another.
MATH = "eliottcassidy2000/math"
MATH_FORK = "claude-monad/math"
LEAN = "claude-monad/math-lean"
MONAD = "claude-monad/monad"

RULES = [
    # New/updated hypothesis or canon theorem in the math repo → formalize it in Lean.
    Rule(MATH, "push", None, "05-knowledge/hypotheses/*",
         lambda c: Action("formalize", LEAN, "math-formalizer",
                          "formalize new/updated hypothesis from math push")),
    Rule(MATH, "push", None, "01-canon/theorems/*",
         lambda c: Action("formalize", LEAN, "math-formalizer",
                          "formalize newly-canonized theorem")),
    # New computation result lands → a reviewer audits it.
    Rule(MATH, "push", None, "05-knowledge/results/*",
         lambda c: Action("review", MATH, "math-reviewer",
                          "audit fresh computation result")),
    # A Lean formalization PR opened/updated → reviewer checks it.
    Rule(LEAN, "pull_request", "opened",
         None, lambda c: Action("review", LEAN, "math-reviewer",
                                "review opened Lean formalization PR")),
    Rule(LEAN, "pull_request", "synchronize",
         None, lambda c: Action("review", LEAN, "math-reviewer",
                                "re-review updated Lean PR")),
    # A task file was committed to the queue → kick the dispatcher to place it now.
    Rule(MONAD, "push", None, "meta/coordination/tasks/*",
         lambda c: Action("merge", MONAD, None,
                          "task emitted to queue → run dispatcher")),
    # A PR merged anywhere → emit a downstream follow-up (push/cleanup).
    Rule(LEAN, "pull_request", "closed",
         None, lambda c: Action("push", LEAN, None,
                                "Lean PR closed → sync + emit any follow-ups")
         if c.get("merged") else None),
]


def match(repo, event, action, paths, ctx=None) -> list[Action]:
    ctx = ctx or {}
    out = []
    for r in RULES:
        if r.matches(repo, event, action, paths):
            a = r.make(ctx)
            if a is not None:
                out.append(a)
    return out
