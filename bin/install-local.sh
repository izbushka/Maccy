#!/bin/sh
# Builds Maccy with an ad-hoc signature and installs it to /Applications.
set -eu

cd "$(dirname "$0")/.."

xcodebuild \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=NO \
  build > build.log 2>&1 || { grep -E "error:" build.log; echo "Build failed, see build.log"; exit 1; }

app=build/Build/Products/Release/Maccy.app
codesign --verify --deep --strict "$app"

osascript -e 'quit app "Maccy"' 2>/dev/null || true
while pgrep -x Maccy >/dev/null; do sleep 0.5; done

rm -rf /Applications/Maccy.app
ditto "$app" /Applications/Maccy.app
open /Applications/Maccy.app
echo "Installed /Applications/Maccy.app"
