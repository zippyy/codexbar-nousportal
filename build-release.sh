#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-}"
UPSTREAM_SHA="${2:-unknown}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: bash build-release.sh <version> [codexbar-upstream-sha]" >&2
  exit 2
fi

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "ERROR: version must look like v1.2.3 or v1.2.3-beta.1" >&2
  exit 2
fi

for required in README.md apply.sh overlay; do
  if [[ ! -e "$ROOT/$required" ]]; then
    echo "ERROR: required release input is missing: $required" >&2
    exit 1
  fi
done

NAME="codexbar-nousportal-${VERSION}"
DIST="$ROOT/dist"
STAGE="$DIST/$NAME"

rm -rf "$DIST"
mkdir -p "$STAGE"

cp "$ROOT/README.md" "$STAGE/README.md"
cp "$ROOT/apply.sh" "$STAGE/apply.sh"
cp -R "$ROOT/overlay" "$STAGE/overlay"

cat > "$STAGE/BUILD-METADATA.txt" <<EOF
CodexBar Nous Portal Provider
Release: $VERSION
Provider repository: https://github.com/zippyy/codexbar-nousportal
Validated CodexBar commit: $UPSTREAM_SHA
Built at (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

cat > "$STAGE/INSTALL.txt" <<'EOF'
Install into a CodexBar source checkout:

  git clone https://github.com/steipete/CodexBar.git
  cd codexbar-nousportal-<version>
  ./apply.sh ../CodexBar
  cd ../CodexBar
  ./Scripts/compile_and_run.sh

Then enable Settings -> Providers -> Nous Portal.

Authentication is reused from Hermes Agent (~/.hermes/auth.json).
If needed, authenticate first with:

  hermes portal
EOF

(
  cd "$DIST"
  /usr/bin/zip -qry "$NAME.zip" "$NAME"
  /usr/bin/tar -czf "$NAME.tar.gz" "$NAME"
)

(
  cd "$DIST"
  shasum -a 256 "$NAME.zip" "$NAME.tar.gz" > "$NAME.sha256"
)

rm -rf "$STAGE"

printf 'Built release assets:\n'
ls -lh "$DIST/$NAME.zip" "$DIST/$NAME.tar.gz" "$DIST/$NAME.sha256"
