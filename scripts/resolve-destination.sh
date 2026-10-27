#!/bin/zsh
set -euo pipefail

# Prints an xcodebuild -destination for an iPhone simulator that exists on this machine, so CI and
# local runs don't hard-code a device name that a newer Xcode image may not have. Prefers the newest
# iOS runtime (the app needs iOS 26 or later), then a Pro model. Set SIMULATOR_ID to force one.

if [[ -n "${SIMULATOR_ID:-}" ]]; then
    print "platform=iOS Simulator,id=${SIMULATOR_ID}"
    exit 0
fi

xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, re, sys

data = json.load(sys.stdin)["devices"]
candidates = []
for runtime, devices in data.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    if version < (26, 0):
        continue
    for device in devices:
        if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
            pro = "Pro" in device["name"] and "Max" not in device["name"]
            candidates.append((version, pro, device["udid"], device["name"]))

if not candidates:
    sys.stderr.write("No available iPhone simulator on iOS 26 or later. Install one in Xcode > Settings > Components.\n")
    sys.exit(1)

candidates.sort(reverse=True)
version, _, udid, name = candidates[0]
sys.stderr.write("Using %s (iOS %d.%d)\n" % (name, version[0], version[1]))
print("platform=iOS Simulator,id=%s" % udid)
'
