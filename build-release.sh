#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
CODEXBAR_SHA="${2:-unknown}"
HELPER_BIN="${3:-}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 vX.Y.Z [codexbar-sha] [helper-binary]" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$ROOT/dist"
PLUGIN="$DIST/codexbar-nousportal-$VERSION.js"
HELPER="$DIST/codexbar-nousportal-helper-$VERSION"
INSTALLER="$DIST/install-helper-$VERSION.sh"
BUNDLE="$DIST/codexbar-nousportal-$VERSION-macos.zip"
METADATA="$DIST/codexbar-nousportal-$VERSION.txt"
CHECKSUMS="$DIST/codexbar-nousportal-$VERSION.sha256"

rm -rf "$DIST"
mkdir -p "$DIST"

cp "$ROOT/nousportal.js" "$PLUGIN"
cp "$ROOT/install-helper.sh" "$INSTALLER"
chmod 0755 "$INSTALLER"

if [[ -n "$HELPER_BIN" ]]; then
  cp "$HELPER_BIN" "$HELPER"
  chmod 0755 "$HELPER"
fi

cat > "$METADATA" <<EOF
CodexBar Nous Portal Plugin
Version: $VERSION
Plugin ID: nous-portal
Helper URL: http://127.0.0.1:38417
Tested CodexBar commit: $CODEXBAR_SHA
Source repository: https://github.com/zippyy/codexbar-nousportal
Install plugin: CodexBar > Settings > Plugins > Install…
EOF

if [[ -f "$HELPER" ]]; then
  bundle_dir="$DIST/bundle"
  mkdir -p "$bundle_dir"
  cp "$PLUGIN" "$bundle_dir/"
  cp "$HELPER" "$bundle_dir/"
  cp "$INSTALLER" "$bundle_dir/"
  cp "$METADATA" "$bundle_dir/README.txt"
  (
    cd "$bundle_dir"
    zip -q -r "$BUNDLE" .
  )
  rm -rf "$bundle_dir"
fi

(
  cd "$DIST"
  files=("$(basename "$PLUGIN")" "$(basename "$INSTALLER")" "$(basename "$METADATA")")
  [[ -f "$HELPER" ]] && files+=("$(basename "$HELPER")")
  [[ -f "$BUNDLE" ]] && files+=("$(basename "$BUNDLE")")
  shasum -a 256 "${files[@]}" > "$(basename "$CHECKSUMS")"
)

printf 'Built release assets:\n'
find "$DIST" -maxdepth 1 -type f -print | sort
