#!/bin/sh
# Builds Drift.app into ./build
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Drift.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Drift "$APP/Contents/MacOS/Drift"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
