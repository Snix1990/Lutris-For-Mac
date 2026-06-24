#!/bin/bash
set -e

CONFIG="${1:-debug}"
PROJECT="LutrisForMac"
BUNDLE="$PROJECT.app"

if [ "$CONFIG" = "release" ]; then
    BUILD_DIR=".build/release"
    FLAGS="--configuration release"
else
    BUILD_DIR=".build/debug"
    FLAGS=""
fi

echo "==> Building $PROJECT ($CONFIG)..."

swift build --product LutrisForMac $FLAGS
swift build --product LutrisForMacConsole $FLAGS

echo "==> Creating $BUNDLE ..."
rm -rf "$BUNDLE"

mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BUILD_DIR/LutrisForMac"        "$BUNDLE/Contents/MacOS/"
cp "$BUILD_DIR/LutrisForMacConsole" "$BUNDLE/Contents/MacOS/"
cp "Sources/LutrisForMacApp/Info.plist" "$BUNDLE/Contents/"

cp -R "Sources/LutrisForMacApp/Locals" "$BUNDLE/Contents/Resources/Locals"

if [ -f "Sources/LutrisForMacApp/AppIcon.icns" ]; then
    cp "Sources/LutrisForMacApp/AppIcon.icns" "$BUNDLE/Contents/Resources/"
fi

echo "==> Fertig: $BUNDLE"
echo "    Desktop:  $BUNDLE/Contents/MacOS/LutrisForMac"
echo "    Console:  $BUNDLE/Contents/MacOS/LutrisForMacConsole"
echo ""
echo "    Starten via: open $BUNDLE"
