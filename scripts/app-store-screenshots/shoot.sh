#!/bin/zsh
# Usage: shoot.sh <sim-id> <out-dir> [Dark|Light] [en|it]
SIM=$1; OUT=$2; THEME=${3:-Dark}; LANG_CODE=${4:-en}
cd "$(dirname "$0")/../.."
xcrun simctl boot $SIM 2>/dev/null; xcrun simctl bootstatus $SIM -b >/dev/null
xcrun simctl keychain $SIM reset
xcrun simctl status_bar $SIM override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl privacy $SIM grant microphone com.mattianalytics.snipnote 2>/dev/null
rm -rf "$OUT"
TEST_RUNNER_SNIPNOTE_SHOTS_DIR="$OUT" TEST_RUNNER_SNIPNOTE_SCREENSHOT_THEME=$THEME TEST_RUNNER_SNIPNOTE_SCREENSHOT_LANGUAGE=$LANG_CODE \
  xcodebuild test -project SnipNote.xcodeproj -scheme SnipNote -destination "platform=iOS Simulator,id=$SIM" \
  -parallel-testing-enabled NO -only-testing:SnipNoteUITests/AppStoreScreenshotsUITests > "$OUT.log" 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" "$OUT.log" | head
mkdir -p "$OUT/small"; for f in "$OUT"/*.png; do sips -Z 900 "$f" --out "$OUT/small/$(basename $f)" >/dev/null; done
ls "$OUT" | grep png
