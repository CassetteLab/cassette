#!/usr/bin/env python3
"""Fails when a localized string does not reach the BUILT app bundle.

The string catalog is not the source of truth for this check — the compiled bundle is.
A malformed catalog entry (for instance language codes written at the entry's root
instead of under "localizations") still compiles, still reads correctly in Xcode, and
still ships English to every other language. Nothing in the catalog looks wrong, so a
catalog-only check passes; only reading the compiled .strings/.stringsdict catches it.
That is why this runs after the build.

Entries deliberately excluded: `extractionState: stale` (no longer referenced from
source, so never shown) and `shouldTranslate: false`.

Usage: verify-i18n.py <app-bundle-or-search-dir> [--catalog PATH] [--warn-only]
"""

import json
import pathlib
import subprocess
import sys

DEFAULT_CATALOG = "Cassette/Localizable.xcstrings"


def die(message):
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(2)


def find_app(target):
    """Accept an .app directly, or a directory to search for one."""
    path = pathlib.Path(target)
    if not path.exists():
        die(f"path not found: {target}")
    if path.suffix == ".app":
        return path
    apps = sorted(path.rglob("*.app"))
    if not apps:
        die(f"no .app bundle found under {target}")
    # Prefer the main app over any nested .appex/extension bundle.
    for app in apps:
        if app.name == "Cassette.app":
            return app
    return apps[0]


def resources_dir(app):
    """iOS keeps .lproj at the bundle root; macOS puts them in Contents/Resources."""
    macos = app / "Contents" / "Resources"
    return macos if macos.is_dir() else app


def read_plist(path):
    if not path.exists():
        return {}
    try:
        out = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(path)],
            capture_output=True, check=True,
        ).stdout
    except subprocess.CalledProcessError as error:
        die(f"could not read {path}: {error.stderr.decode(errors='replace').strip()}")
    return json.loads(out)


def translatable(entry):
    return (
        entry.get("extractionState") != "stale"
        and entry.get("shouldTranslate", True) is not False
    )


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    warn_only = "--warn-only" in flags
    catalog_path = DEFAULT_CATALOG
    for flag in list(flags):
        if flag.startswith("--catalog="):
            catalog_path = flag.split("=", 1)[1]
    if not args:
        die("usage: verify-i18n.py <app-bundle-or-search-dir> [--catalog PATH] [--warn-only]")

    app = find_app(args[0])
    resources = resources_dir(app)

    catalog_file = pathlib.Path(catalog_path)
    if not catalog_file.exists():
        die(f"string catalog not found: {catalog_path} (run from the repository root)")
    catalog = json.loads(catalog_file.read_text(encoding="utf-8"))
    source_language = catalog.get("sourceLanguage", "en")
    entries = catalog["strings"]

    languages = sorted(
        {lang for entry in entries.values() for lang in entry.get("localizations", {})}
        - {source_language}
    )
    if not languages:
        die(f"no target languages found in {catalog_path}")

    keys = [key for key, entry in entries.items() if translatable(entry)]
    problems = []

    for language in languages:
        lproj = resources / f"{language}.lproj"
        if not lproj.is_dir():
            problems.append(f"{language}: no {language}.lproj in {resources}")
            continue
        strings = read_plist(lproj / "Localizable.strings")
        stringsdict = read_plist(lproj / "Localizable.stringsdict")
        for key in keys:
            if key in stringsdict:
                continue
            if key not in strings:
                problems.append(f"{language}: not localized: {key!r}")
            elif strings[key] == "" and key != "":
                problems.append(f"{language}: empty translation: {key!r}")

    print(f"{app.name}: checked {len(keys)} strings x {len(languages)} languages "
          f"({', '.join(languages)})")

    if not problems:
        print("All strings resolve in every language.")
        return 0

    for problem in problems:
        print(f"  {problem}")
    summary = (
        f"{len(problems)} string(s) fall back to {source_language} in the built bundle. "
        "A catalog entry whose languages are not nested under \"localizations\" compiles "
        "cleanly and produces exactly this."
    )
    if warn_only:
        print(f"::warning::{summary} Reported, not blocking.")
        return 0
    print(f"::error::{summary}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
