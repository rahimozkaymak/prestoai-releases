#!/bin/bash
set -euo pipefail

# Build a professional DMG for Presto AI
# Usage: ./scripts/build-dmg.sh [path-to-app]

APP_PATH="${1:-build/export/PrestoAI.app}"
DMG_OUTPUT="build/PrestoAI.dmg"
DMG_TEMP="build/rw.PrestoAI.dmg"
VOLUME_NAME="Presto AI"
BACKGROUND="dmg-resources/background.tiff"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    echo "Usage: $0 [path-to-PrestoAI.app]"
    exit 1
fi

# Eject any existing volume with the same name
if [ -d "/Volumes/$VOLUME_NAME" ]; then
    echo "Ejecting existing '$VOLUME_NAME' volume..."
    hdiutil detach "/Volumes/$VOLUME_NAME" -force 2>/dev/null || true
    sleep 1
fi
# Also eject numbered variants
for v in "/Volumes/${VOLUME_NAME} "?; do
    [ -d "$v" ] && hdiutil detach "$v" -force 2>/dev/null || true
done

# Clean up
rm -f "$DMG_OUTPUT" "$DMG_TEMP"

# Get app size and add padding
APP_SIZE_KB=$(du -sk "$APP_PATH" | cut -f1)
DMG_SIZE_KB=$((APP_SIZE_KB + 10240))

echo "Creating writable DMG (${DMG_SIZE_KB}KB)..."
hdiutil create -srcfolder "$APP_PATH" -volname "$VOLUME_NAME" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" \
    -format UDRW -size "${DMG_SIZE_KB}k" "$DMG_TEMP"

echo "Mounting..."
MOUNT_DIR=$(hdiutil attach -readwrite -noverify "$DMG_TEMP" | grep '/Volumes/' | sed 's/.*\/Volumes/\/Volumes/')
echo "Mounted at: $MOUNT_DIR"

# Create Applications symlink
ln -sf /Applications "$MOUNT_DIR/Applications"

# Copy background
mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND" "$MOUNT_DIR/.background/background.tiff"

echo "Configuring Finder layout..."
# Extract the actual volume name from mount path (handles "Presto AI 1" etc.)
ACTUAL_VOL_NAME=$(basename "$MOUNT_DIR")
echo "Using volume name: $ACTUAL_VOL_NAME"

# Use AppleScript to set exact window properties
# Use Python to write .DS_Store directly (avoids flaky AppleScript)
python3 - "$MOUNT_DIR" <<'PYEOF'
import struct, sys, os

mount = sys.argv[1]
bg_file = ".background/background.tiff"

# We'll use a simpler approach: set up via AppleScript with retries
import subprocess, time

vol_name = os.path.basename(mount)
for attempt in range(3):
    result = subprocess.run(["osascript", "-e", f'''
        tell application "Finder"
            activate
            delay 1
            tell disk "{vol_name}"
                open
                delay 3
                set theWindow to container window
                set current view of theWindow to icon view
                set toolbar visible of theWindow to false
                set statusbar visible of theWindow to false
                set bounds of theWindow to {{200, 120, 860, 542}}
                set viewOptions to icon view options of theWindow
                set arrangement of viewOptions to not arranged
                set icon size of viewOptions to 128
                set text size of viewOptions to 14
                set background picture of viewOptions to file ".background:background.tiff"
                delay 1
                set position of item "PrestoAI.app" of theWindow to {{165, 160}}
                set position of item "Applications" of theWindow to {{495, 160}}
                close theWindow
                open
                delay 1
                close
            end tell
        end tell
    '''], capture_output=True, text=True)
    if result.returncode == 0:
        print("AppleScript succeeded")
        break
    print(f"Attempt {attempt+1} failed: {result.stderr.strip()}")
    time.sleep(2)
else:
    print("WARNING: AppleScript failed after retries, background may not be set")
    sys.exit(1)
PYEOF

# Wait for .DS_Store to be written
sync
sleep 2

echo "Ejecting..."
hdiutil detach "$MOUNT_DIR"

echo "Compressing..."
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUTPUT"
rm -f "$DMG_TEMP"

echo ""
echo "DMG created: $DMG_OUTPUT"
echo "Size: $(du -h "$DMG_OUTPUT" | cut -f1)"
