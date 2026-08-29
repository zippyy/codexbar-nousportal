#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
CODEXBAR_SHA="${2:-unknown}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 vX.Y.Z [codexbar-sha]" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$ROOT/dist"
ASSET="$DIST/codexbar-nousportal-$VERSION.js"
METADATA="$DIST/codexbar-nousportal-$VERSION.txt"
CHECKSUMS="$DIST/codexbar-nousportal-$VERSION.sha256"

rm -rf "$DIST"
mkdir -p "$DIST"

cp "$ROOT/nousportal.js" "$ASSET"

cat > "$METADATA" <<EOF
CodexBar Nous Portal Plugin
Version: $VERSION
Plugin ID: nous-portal
Tested CodexBar commit: $CODEXBAR_SHA
Source repository: https://github.com/zippyy/codexbar-nousportal
Install: CodexBar > Settings > Plugins > Install…
EOF

(
  cd "$DIST"
  shasum -a 256 "$(basename "$ASSET")" "$(basename "$METADATA")" > "$(basename "$CHECKSUMS")"
)

printf 'Built release assets:\n'
printf '  %s\n' "$ASSET" "$METADATA" "$CHECKSUMS"
