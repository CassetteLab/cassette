#!/usr/bin/env python3
"""Regenerates SUPPORTERS.md from supporters.json.

supporters.json is the only file to edit when someone is added or removed: this script
writes SUPPORTERS.md from it, and the app bundles the JSON itself at build time.

The script refuses a file it would render wrongly rather than guessing: a missing name,
a `since` that is not YYYY-MM, an entry older than the one before it (the list is kept
oldest first), or a field outside name/since/url — which is also what stops an amount
from being recorded by mistake.

Usage: scripts/generate-supporters.py
"""

import json
import pathlib
import re
import sys
import unicodedata
from urllib.parse import urlparse

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = REPO_ROOT / "supporters.json"
OUTPUT = REPO_ROOT / "SUPPORTERS.md"

KOFI_URL = "https://ko-fi.com/mathieudbrt"
ISSUES_URL = "https://github.com/CassetteLab/cassette/issues"
CONTACT_EMAIL = "support@getcassette.app"

ALLOWED_FIELDS = {"name", "since", "url"}
SINCE_PATTERN = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")

# Names are chosen by supporters, so anything Markdown would interpret is escaped: inline
# formatting, links and HTML anywhere, and block markers where a list item's text begins.
INLINE_SYNTAX = re.compile(r"([\\`*_\[\]<>|~&])")
BLOCK_START = re.compile(r"^(\d+)?([#+\->=.)])")


def die(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def escape_markdown(text):
    text = INLINE_SYNTAX.sub(r"\\\1", text)
    return BLOCK_START.sub(lambda m: f"{m.group(1) or ''}\\{m.group(2)}", text)


def validated_supporters(document):
    if not isinstance(document, dict) or not isinstance(document.get("supporters"), list):
        die(f'{SOURCE.name} must be an object with a "supporters" array')

    supporters = []
    previous_since = ""
    for index, entry in enumerate(document["supporters"]):
        where = f"supporters[{index}]"
        if not isinstance(entry, dict):
            die(f"{where} must be an object")

        unknown = sorted(set(entry) - ALLOWED_FIELDS)
        if unknown:
            die(f"{where} has unexpected field(s) {', '.join(unknown)}; "
                f"allowed: {', '.join(sorted(ALLOWED_FIELDS))} (never record an amount)")

        name = entry.get("name")
        if not isinstance(name, str) or not name.strip():
            die(f'{where} needs a non-empty "name"')
        if any(unicodedata.category(character) in ("Cc", "Zl", "Zp") for character in name):
            die(f'{where} "name" must be a single line')

        since = entry.get("since")
        if not isinstance(since, str) or not SINCE_PATTERN.match(since):
            die(f'{where} ({name.strip()}) needs "since" as YYYY-MM')
        if since < previous_since:
            die(f"{where} ({name.strip()}) is dated {since}, before the entry above it "
                f"({previous_since}); the list is kept oldest first")
        previous_since = since

        url = entry.get("url")
        if url is not None:
            parsed = urlparse(url) if isinstance(url, str) else None
            if (parsed is None or parsed.scheme not in ("http", "https") or not parsed.netloc
                    or any(character.isspace() or character in "<>" for character in url)):
                die(f'{where} ({name.strip()}) has an invalid "url"; use a full http(s) link')

        supporters.append({"name": name.strip(), "url": url})
    return supporters


def render(supporters):
    lines = [
        "<!-- Generated from supporters.json by scripts/generate-supporters.py. "
        "Edit the JSON, not this file. -->",
        "",
        "# Supporters",
        "",
        "Cassette is free, forever. This page thanks the people who chose to support it "
        f"on [Ko-fi]({KOFI_URL}).",
        "",
        "Everyone is listed by the name they chose, at the same level, in the order they "
        "joined. No amounts, no tiers, no ranking. The same list is credited in the app, "
        "under Settings.",
        "",
    ]

    if supporters:
        for supporter in supporters:
            name = escape_markdown(supporter["name"])
            url = supporter["url"]
            lines.append(f"- [{name}](<{url}>)" if url else f"- {name}")
    else:
        lines.append("Nobody is listed yet: the first public supporter on Ko-fi will be "
                     "credited here.")

    lines += [
        "",
        "## Being listed",
        "",
        "Only support marked public on Ko-fi is credited here; support given privately "
        "stays private. To change or remove your name at any time, write to "
        f"[{CONTACT_EMAIL}](mailto:{CONTACT_EMAIL}) or [open an issue]({ISSUES_URL}).",
        "",
    ]
    return "\n".join(lines)


def main():
    try:
        document = json.loads(SOURCE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        die(f"{SOURCE} not found")
    except json.JSONDecodeError as error:
        die(f"{SOURCE.name} is not valid JSON: {error}")

    supporters = validated_supporters(document)
    OUTPUT.write_text(render(supporters), encoding="utf-8")
    count = len(supporters)
    print(f"Wrote {OUTPUT.name} ({count} supporter{'' if count == 1 else 's'}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
