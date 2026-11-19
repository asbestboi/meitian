#!/usr/bin/env bash
# Installs the simulator build, launches it twice (fresh, then as an onboarded user with data),
# and fails with the crash report if the app dies. Screenshots go to build/smoke.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=build/smoke; mkdir -p "$OUT"
APP=build/sim/Build/Products/Release-iphonesimulator/Meitian.app
BUNDLE=com.asbestboi.meitian

DEVICE=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
for rt,devs in d.items():
    if "iOS" in rt:
        for x in devs:
            if x["name"].startswith("iPhone"): print(x["udid"]); sys.exit()')
echo "device: $DEVICE"
xcrun simctl boot "$DEVICE"; xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl install "$DEVICE" "$APP"

failed=0
run() {
    local name=$1
    rm -rf ~/Library/Logs/DiagnosticReports/Meitian* 2>/dev/null
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null
    local launched pid
    launched=$(xcrun simctl launch "$DEVICE" "$BUNDLE" 2>&1)
    echo "$launched" > "$OUT/$name-console.txt"
    pid=${launched##*: }
    sleep 15
    xcrun simctl io "$DEVICE" screenshot "$OUT/$name.png" >/dev/null 2>&1
    # simulator apps are host processes, so ps sees them
    if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
        echo "✅ $name: app is running"
    else
        echo "❌ $name: app is NOT running (crashed)"; failed=1
    fi
    sleep 2
    for f in ~/Library/Logs/DiagnosticReports/Meitian*; do
        [ -f "$f" ] || continue
        cp "$f" "$OUT/"
        echo "----- crash report ($name): $f"
        head -c 12000 "$f"
        failed=1
    done
    echo "----- console ($name)"; tail -40 "$OUT/$name-console.txt"
    echo "----- system log ($name)"
    xcrun simctl spawn "$DEVICE" log show --last 1m --style compact \
        --predicate 'process == "Meitian" AND (messageType == error OR messageType == fault OR eventMessage CONTAINS[c] "fatal" OR eventMessage CONTAINS[c] "crash")' \
        2>/dev/null | tail -60
}

run fresh

# seed an onboarded user with a little history, like a real phone after updating
DATA=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)
mkdir -p "$DATA/Documents"
TODAY=$(date +%Y-%m-%d)
cat > "$DATA/Documents/meitian.json" <<JSON
{"profile":{"name":"Tester","claimedLevel":1,"confirmedLevel":1,"dailyGoal":5,"onboarded":true,
 "reminderOn":false,"reminderHour":19,"reminderMinute":0,"preferredFriend":"chinese"},
 "cards":{"1-你好":{"box":2,"due":0,"correct":1,"wrong":0,"learnedOn":"$TODAY"}},
 "days":{"$TODAY":{"newWordIds":[],"learnedDone":true,"reviewed":1,"xp":60}},"xp":60}
JSON
run onboarded

exit $failed
