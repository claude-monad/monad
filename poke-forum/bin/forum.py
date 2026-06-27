#!/usr/bin/env python3
"""Small helper for repo-local Poke Forum posts and comments."""

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POSTS = ROOT / "posts"


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", text.lower()).strip("-")
    return slug[:72] or "untitled"


def resolve_post(value: str) -> Path:
    POSTS.mkdir(parents=True, exist_ok=True)
    if value == "latest":
        posts = sorted(POSTS.glob("*.md"))
        if not posts:
            raise SystemExit("forum: no posts found")
        return posts[-1]

    path = Path(value)
    if not path.is_absolute():
        if path.parent == Path("."):
            path = POSTS / path
        else:
            path = Path.cwd() / path
    if not path.exists():
        raise SystemExit(f"forum: post not found: {path}")
    return path


def cmd_latest(_: argparse.Namespace) -> int:
    print(resolve_post("latest"))
    return 0


def cmd_new(args: argparse.Namespace) -> int:
    POSTS.mkdir(parents=True, exist_ok=True)
    title = args.title.strip()
    path = POSTS / f"{stamp()}-{slugify(title)}.md"
    body = sys.stdin.read().strip()
    front = (
        "---\n"
        f"title: {title}\n"
        f"created: {now_utc()}\n"
        f"role: {args.author}\n"
        "topics: []\n"
        "---\n\n"
    )
    if body:
        text = front + body.rstrip() + "\n"
    else:
        text = front + "## Topics\n\n## Web Search\n\n## Comment Invitations\n\n"
    if "\n## Comments" not in text:
        text = text.rstrip() + "\n\n## Comments\n"
    path.write_text(text, encoding="utf-8")
    print(path)
    return 0


def cmd_comment(args: argparse.Namespace) -> int:
    path = resolve_post(args.post)
    author = args.author.strip() or "anonymous"
    body = sys.stdin.read().strip()
    if not body:
        raise SystemExit("forum: refusing empty comment")
    comment = (
        "\n\n"
        f"### Comment by {author} at {now_utc()}\n\n"
        f"{body.rstrip()}\n"
    )
    with path.open("a", encoding="utf-8") as fh:
        fh.write(comment)
    print(path)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    latest = sub.add_parser("latest", help="print latest post path")
    latest.set_defaults(func=cmd_latest)

    new = sub.add_parser("new", help="create a new post from stdin")
    new.add_argument("--title", required=True)
    new.add_argument("--author", default="poke-coordinator")
    new.set_defaults(func=cmd_new)

    comment = sub.add_parser("comment", help="append a comment from stdin")
    comment.add_argument("--post", default="latest")
    comment.add_argument("--author", required=True)
    comment.set_defaults(func=cmd_comment)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
