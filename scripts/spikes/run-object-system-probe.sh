#!/bin/sh
# Builds a probe for the iOS Simulator and runs it there (PaperKit 27's element
# API is not on a macOS 26 host).
# Usage: scripts/spikes/run-object-system-probe.sh [simulator name or UDID, default booted] [source file]
set -e
cd "$(dirname "$0")/../.."
device="${1:-booted}"
source="${2:-scripts/spikes/object-system-probe.swift}"
out="$(mktemp -d)/probe"
xcrun --sdk iphonesimulator swiftc -O -parse-as-library \
    -target arm64-apple-ios27.0-simulator \
    -o "$out" "$source"
xcrun simctl spawn "$device" "$out"
