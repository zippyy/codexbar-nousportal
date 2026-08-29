#!/usr/bin/env bash
set -euo pipefail

PORT=38417
LABEL="com.zippyy.codexbar-nousportal-helper"
BIN_NAME="codexbar-nousportal-helper"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_PATH="$INSTALL_DIR/$BIN_NAME"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SOURCE_BIN="${1:-}"
if [[ -z "$SOURCE_BIN" ]]; then
  for candidate in \
    "$SCRIPT_DIR/$BIN_NAME" \
    "$SCRIPT_DIR"/codexbar-nousportal-helper-v*; do
    if [[ -f "$candidate" ]]; then
      SOURCE_BIN="$candidate"
      break
    fi
  done
fi

if [[ -z "$SOURCE_BIN" || ! -f "$SOURCE_BIN" ]]; then
  echo "Helper binary not found." >&2
  echo "Run this installer from the extracted release bundle, or pass the helper binary path:" >&2
  echo "  $0 /path/to/codexbar-nousportal-helper" >&2
  exit 2
fi

mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/CodexBar"
cp "$SOURCE_BIN" "$INSTALL_PATH"
chmod 0755 "$INSTALL_PATH"
xattr -d com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/CodexBar/nousportal-helper.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/CodexBar/nousportal-helper.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

for _ in {1..20}; do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    echo "Nous Portal helper installed and running."
    echo "Helper URL: http://127.0.0.1:$PORT"
    exit 0
  fi
  sleep 0.25
done

echo "Helper was installed but did not become healthy." >&2
echo "Check: $HOME/Library/Logs/CodexBar/nousportal-helper.log" >&2
exit 1
