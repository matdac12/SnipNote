#!/bin/zsh
# Regenerates every App Store image in one go. See README.md.
# Usage: scripts/app-store-screenshots/run-all.sh [output-dir] [en|it]
set -e
HERE=${0:A:h}
REPO=${HERE:h:h}
VERSION=$(grep -m1 "MARKETING_VERSION = " "$REPO/SnipNote.xcodeproj/project.pbxproj" | sed -E 's/.*= ([^;]*);/\1/')
OUT=${1:-${REPO:h}/snipnote-marketing/App Store $VERSION}
LANG_CODE=${2:-en}
WORK=$(mktemp -d)

sim_id() { xcrun simctl list devices available | grep -m1 "$1 (" | grep -oE '[0-9A-F-]{36}'; }
IPHONE=$(sim_id "iPhone 17 Pro Max")
IPAD=$(sim_id "iPad Pro 13-inch (M5)")
[[ -n $IPHONE && -n $IPAD ]] || { echo "Missing simulator (iPhone 17 Pro Max or iPad Pro 13-inch (M5))"; exit 1; }

echo "▶ Capturing on iPhone and iPad (builds the app, ~10 min)"
"$HERE/shoot.sh" "$IPHONE" "$WORK/iphone" Dark "$LANG_CODE"
"$HERE/shoot.sh" "$IPAD" "$WORK/ipad" Dark "$LANG_CODE"

echo "▶ Framing"
python3 -I "$HERE/frame.py" "$WORK/iphone" "$WORK/framed-iphone" iphone "$LANG_CODE"
python3 -I "$HERE/frame.py" "$WORK/ipad" "$OUT/iPad 13 inch/Framed" ipad "$LANG_CODE"

# App Store Connect's iPhone slot ("Dynamic Island, medium display") takes 1206x2622, not the
# 1320x2868 the 6.9-inch simulator produces; the aspect ratio differs by 0.06%.
mkdir -p "$OUT/iPhone 6.3 inch/Framed" "$OUT/iPhone 6.3 inch/Raw" "$OUT/iPad 13 inch/Raw"
for f in "$WORK/framed-iphone"/*.png; do sips -z 2622 1206 "$f" --out "$OUT/iPhone 6.3 inch/Framed/${f:t}" >/dev/null; done
i=1
for name in 01-home 03-detail 04-detail-scrolled 11-recording 02-transcriptions 06-search 09-transcription 10-dictation 08-settings; do
  target=$(printf "%02d-%s.png" $i ${name#*-})
  sips -z 2622 1206 "$WORK/iphone/$name.png" --out "$OUT/iPhone 6.3 inch/Raw/$target" >/dev/null
  cp "$WORK/ipad/$name.png" "$OUT/iPad 13 inch/Raw/$target"
  i=$((i + 1))
done

echo "▶ Product page header and search results"
python3 -I "$HERE/hero.py" "$WORK/iphone" "$OUT/Header and Search Results" "$LANG_CODE"
rm -f "$OUT/Header and Search Results/.widget.png"

rm -rf "$WORK"
echo "✅ Done: $OUT"
