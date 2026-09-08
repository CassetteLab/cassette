#!/usr/bin/env python3
"""Print the UDID of the newest available iPhone simulator."""
import json, subprocess, sys

raw = subprocess.run(
    ["xcrun", "simctl", "list", "devices", "available", "--json"],
    capture_output=True, text=True, check=True,
).stdout
best = None
for runtime, devices in json.loads(raw)["devices"].items():
    if "iOS" not in runtime:
        continue
    version = runtime.rsplit(".iOS-", 1)[-1].replace("-", ".")
    try:
        key = tuple(int(p) for p in version.split("."))
    except ValueError:
        continue
    for device in devices:
        if not device.get("isAvailable") or "iPhone" not in device["name"]:
            continue
        if best is None or key > best[0]:
            best = (key, device["udid"], device["name"], version)
if best is None:
    sys.exit("No available iPhone simulator found")
print(best[1])
print(f"{best[2]} (iOS {best[3]})", file=sys.stderr)
