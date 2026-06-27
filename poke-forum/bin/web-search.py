#!/usr/bin/env python3
"""Minimal web search helper for Poke Forum agents.

It queries DuckDuckGo Lite and prints a small list of titles and links. This is a
helper for lightweight source discovery, not a substitute for reading sources.
"""

from __future__ import annotations

import argparse
import html
from html.parser import HTMLParser
import re
import sys
import urllib.parse
import urllib.request


def clean_text(text: str) -> str:
    text = re.sub(r"<[^>]+>", " ", text)
    text = html.unescape(text)
    return re.sub(r"\s+", " ", text).strip()


def decode_href(href: str) -> str:
    href = html.unescape(href)
    parsed = urllib.parse.urlparse(href)
    qs = urllib.parse.parse_qs(parsed.query)
    if "uddg" in qs and qs["uddg"]:
        return qs["uddg"][0]
    if href.startswith("//"):
        return "https:" + href
    if href.startswith("/"):
        return "https://duckduckgo.com" + href
    return href


def search(query: str, limit: int) -> list[tuple[str, str]]:
    url = "https://lite.duckduckgo.com/lite/?" + urllib.parse.urlencode({"q": query})
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=20) as response:
        page = response.read().decode("utf-8", errors="replace")

    parser = ResultParser(limit)
    parser.feed(page)
    return parser.results


class ResultParser(HTMLParser):
    def __init__(self, limit: int) -> None:
        super().__init__()
        self.limit = limit
        self.in_result = False
        self.href = ""
        self.parts: list[str] = []
        self.results: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a" or len(self.results) >= self.limit:
            return
        attr = {k.lower(): v or "" for k, v in attrs}
        classes = set(attr.get("class", "").split())
        if "result-link" in classes:
            self.in_result = True
            self.href = decode_href(attr.get("href", ""))
            self.parts = []

    def handle_data(self, data: str) -> None:
        if self.in_result:
            self.parts.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() != "a" or not self.in_result:
            return
        title = clean_text(" ".join(self.parts))
        href = self.href
        if title and href.startswith("http") and "duckduckgo.com/y.js" not in href:
            self.results.append((title, href))
        self.in_result = False
        self.href = ""
        self.parts = []


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("query")
    parser.add_argument("--limit", type=int, default=5)
    args = parser.parse_args(argv)

    try:
        results = search(args.query, args.limit)
    except Exception as exc:  # noqa: BLE001 - CLI helper should report network failures plainly.
        print(f"web-search: failed: {exc}", file=sys.stderr)
        return 1

    if not results:
        print("web-search: no results", file=sys.stderr)
        return 1

    for i, (title, href) in enumerate(results, 1):
        print(f"{i}. {title}\n   {href}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
