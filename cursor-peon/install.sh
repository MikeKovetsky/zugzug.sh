#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

CURSOR_BIN=""
for c in cursor /Applications/Cursor.app/Contents/Resources/app/bin/cursor; do
  if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then CURSOR_BIN="$c"; break; fi
done
if [ -z "$CURSOR_BIN" ]; then
  echo "Cursor CLI not found. Install via: Cursor → Cmd+Shift+P → 'Shell Command: Install cursor command'"
  exit 1
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "npx required. Install Node.js first."
  exit 1
fi

echo "Packaging extension..."
rm -f peon-mascot-*.vsix
npx --yes @vscode/vsce@latest package --allow-missing-repository --skip-license -o peon-mascot.vsix >/dev/null

echo "Installing into Cursor..."
"$CURSOR_BIN" --install-extension peon-mascot.vsix --force

echo
echo "Done. Reload Cursor window: Cmd+Shift+P → 'Developer: Reload Window'"
echo "Look at the bottom-left of your status bar for the peon."
