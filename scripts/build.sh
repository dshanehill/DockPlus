#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Dock+.app"
TEMPLATE="$APP/Contents/Resources/FolderTemplate.app"
ARCH="$(uname -m)"
mkdir -p "$APP/Contents/MacOS" "$TEMPLATE/Contents/MacOS" "$TEMPLATE/Contents/Resources"
xcrun swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" "$ROOT/Sources/main.swift" -o "$APP/Contents/MacOS/DockPlus" -framework AppKit -framework SwiftUI
cp "$APP/Contents/MacOS/DockPlus" "$TEMPLATE/Contents/MacOS/DockPlus"
python3 - "$APP" "$TEMPLATE" <<'PY'
import plistlib,sys
from pathlib import Path
for path,manager in [(sys.argv[1],True),(sys.argv[2],False)]:
    info={'CFBundleName':'Dock+' if manager else 'Folder','CFBundleDisplayName':'Dock+' if manager else 'Folder',
          'CFBundleIdentifier':'org.dockplus.Manager' if manager else 'org.dockplus.Folder.Template',
          'CFBundleExecutable':'DockPlus','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.1.0',
          'CFBundleVersion':'1','CFBundleIconFile':'AppIcon','LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True,
          'DockPlusManager':manager,'FolderSymbol':'square.grid.2x2.fill','FolderColors':['#2979E8','#60BCFF'],'DefaultApps':[]}
    Path(path,'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
"$APP/Contents/MacOS/DockPlus" --write-icon "$APP/Contents/Resources/AppIcon.icns"
cp "$APP/Contents/Resources/AppIcon.icns" "$TEMPLATE/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier org.dockplus.Folder.Template -r='designated => identifier "org.dockplus.Folder.Template"' "$TEMPLATE"
codesign --force --sign - --identifier org.dockplus.Manager -r='designated => identifier "org.dockplus.Manager"' "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
