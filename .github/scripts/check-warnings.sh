#!/bin/bash
# Fails when a build log contains a compiler warning from our own source.
#
# Dependency checkouts and generated sources are filtered out: a warning inside
# SwiftSonic or AudioStreaming is not something a Cassette pull request can fix,
# and failing on it would make the gate unactionable.
#
# Usage: check-warnings.sh <log> [--warn-only]

set -euo pipefail

log=${1:?usage: check-warnings.sh <log> [--warn-only]}
mode=${2:-}

warnings=$(
    grep -E '\.(swift|m|mm|h|c):[0-9]+:[0-9]+: warning:' "$log" \
        | grep -v '/SourcePackages/' \
        | grep -v '/DerivedData/' \
        | grep -v '/\.spm/' \
        | sed "s|^${GITHUB_WORKSPACE:-$PWD}/||" \
        | sort -u || true
)

if [ -z "$warnings" ]; then
    echo "No first-party compiler warnings."
    exit 0
fi

count=$(printf '%s\n' "$warnings" | wc -l | tr -d ' ')
printf '%s\n' "$warnings"

if [ "$mode" = "--warn-only" ]; then
    echo "::warning::${count} compiler warning(s) — reported, not blocking."
    exit 0
fi

echo "::error::${count} compiler warning(s). Cassette builds warning-free; please resolve them."
exit 1
