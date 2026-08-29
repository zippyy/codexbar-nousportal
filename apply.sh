#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 /path/to/CodexBar" >&2
  exit 2
fi

TARGET="$(cd "$TARGET" && pwd)"
PROVIDERS_FILE="$TARGET/Sources/CodexBarCore/Providers/Providers.swift"

if [[ ! -f "$PROVIDERS_FILE" ]]; then
  echo "ERROR: $TARGET does not look like a CodexBar checkout." >&2
  exit 1
fi

if [[ ! -x "$TARGET/Scripts/regenerate-provider-manifests.sh" ]]; then
  echo "ERROR: CodexBar provider manifest generator is missing." >&2
  exit 1
fi

printf 'Applying Nous Portal provider to %s\n' "$TARGET"

# Keep re-runs idempotent: replace our provider folders rather than nesting a
# second NousPortal directory inside the first one.
rm -rf \
  "$TARGET/Sources/CodexBarCore/Providers/NousPortal" \
  "$TARGET/Sources/CodexBar/Providers/NousPortal"
cp -R "$ROOT/overlay/Sources/CodexBarCore/Providers/NousPortal" \
  "$TARGET/Sources/CodexBarCore/Providers/NousPortal"
cp -R "$ROOT/overlay/Sources/CodexBar/Providers/NousPortal" \
  "$TARGET/Sources/CodexBar/Providers/NousPortal"
cp "$ROOT/overlay/Sources/CodexBar/Resources/ProviderIcon-nousportal.svg" \
  "$TARGET/Sources/CodexBar/Resources/ProviderIcon-nousportal.svg"
cp "$ROOT/overlay/Tests/CodexBarTests/NousPortalUsageFetcherTests.swift" \
  "$TARGET/Tests/CodexBarTests/NousPortalUsageFetcherTests.swift"

python3 - "$PROVIDERS_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
if "    case nousportal\n" not in text:
    anchor = "    case commandcode\n"
    if anchor not in text:
        raise SystemExit("ERROR: could not find Command Code provider anchor in Providers.swift")
    text = text.replace(anchor, anchor + "    case nousportal\n", 1)
    path.write_text(text)
PY

(
  cd "$TARGET"
  Scripts/regenerate-provider-manifests.sh
)

cat <<'MSG'
Nous Portal provider applied.

Next steps:
  1. Build/test CodexBar normally.
  2. Open CodexBar > Settings > Providers.
  3. Enable "Nous Portal".

Authentication is inherited from Hermes (~/.hermes/auth.json). If needed:
  hermes portal
MSG
