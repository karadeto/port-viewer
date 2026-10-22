#!/bin/zsh
# Builds Port Viewer.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Port Viewer.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/PortViewer"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PortViewer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x PortViewer 2>/dev/null || true
    rm -rf "/Applications/Port Viewer.app"
    cp -R "$APP" /Applications/
    open "/Applications/Port Viewer.app"
    echo "Installed to /Applications"
fi
