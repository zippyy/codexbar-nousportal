#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${1:-${TMPDIR:-/tmp}/codexbar-nousportal-check}"

rm -rf "$WORK"
git clone --depth 1 https://github.com/steipete/CodexBar.git "$WORK"
"$ROOT/apply.sh" "$WORK"

cd "$WORK"
swift test --filter NousPortal
