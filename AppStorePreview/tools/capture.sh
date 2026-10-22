#!/bin/zsh
# Builds the Debug simulator app and captures every App Store scene into
# sources/<device>/<scene>.png. Each scene is a fresh launch with
# `-StoreScreens <scene>` (Apps/Shared/App/StoreScreens.swift): the simulated
# Sony connected, saved cameras, a fixed GPS walk.
#
#   ./capture.sh                 # build, then every device
#   ./capture.sh iphone ipad     # some devices (skips the build if SKIP_BUILD=1)
#
# The simulators are created on first use, named "xGRC Shots …", so a run never
# touches anyone's own simulators. Run from anywhere; needs XcodeGen and Xcode.
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

HERE=${0:A:h}
REPO=${HERE:h:h}
BUILD=${TMPDIR:-/tmp}/xgrc-store-build
IOS_APP=$BUILD/Build/Products/Debug-iphonesimulator/xGRC.app
WATCH_APP=$BUILD/Build/Products/Debug-watchsimulator/xGRC.app

# device: simulator name | device type | runtime | app | scene:seconds… | display
# `display` inner: the largest screen, for the iPhone Duo's inner display. Xcode
# has no command to unfold the Duo: unfold "xGRC Shots Duo" by hand first.
# The waits let the Sony connect and the scene play out: `shots` fires its
# last shot 14 s after launch (caught at 15 s, while it still shows Fired),
# `delay` is caught mid-countdown, geotag scenes wait for a few pushes.
typeset -A DEVICES
DEVICES=(
  iphone      "xGRC Shots iPhone|iPhone-17-Pro-Max|iOS-27-0|ios|session:16 shots:15 bulb:10 delay:7 timelapse:16 geotag:16 cameras:16 settings:12"
  duo-outer   "xGRC Shots Duo|iPhone-Duo|iOS-27-1|ios|session:20 shots:15 bulb:12 delay:10 timelapse:22 geotag:20 cameras:20 settings:20"
  duo-inner   "xGRC Shots Duo|iPhone-Duo|iOS-27-1|ios|session:20 shots:15 bulb:12 delay:10 timelapse:22 geotag:20 settings:20|inner"
  ipad        "xGRC Shots iPad|iPad-Pro-13-inch-M5-12GB|iOS-27-0|ios|session:16 shots:15 bulb:10 delay:7 timelapse:16 geotag:16 settings:12"
  watch-ultra "xGRC Shots Ultra|Apple-Watch-Ultra-4-49mm|watchOS-27-0|watch|session:12 shots:15 bulb:8 timelapse:16 geotag:16 controls:10 cameras:10"
  watch-46    "xGRC Shots Watch 46|Apple-Watch-Series-12-46mm|watchOS-27-0|watch|session:12 shots:14.9 bulb:8 timelapse:16 geotag:16 controls:10 cameras:10"
)

wanted=(${@:-iphone duo-outer ipad watch-ultra watch-46})

if [[ ${SKIP_BUILD:-0} != 1 ]]; then
  (cd $REPO && xcodegen generate --quiet)
  xcodebuild -project $REPO/xGRC.xcodeproj -scheme xGRC-iOS -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath $BUILD \
    CODE_SIGNING_ALLOWED=NO build -quiet
fi

udid_for() {  # name type runtime
  local id=$(xcrun simctl list devices -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == sys.argv[1] and d['isAvailable']: print(d['udid']); break" "$1" | head -1)
  [[ -n $id ]] || id=$(xcrun simctl create "$1" com.apple.CoreSimulator.SimDeviceType.$2 com.apple.CoreSimulator.SimRuntime.$3)
  echo $id
}

for device in $wanted; do
  IFS='|' read name type runtime kind scenes display <<< "${DEVICES[$device]}"
  udid=$(udid_for "$name" $type $runtime)
  xcrun simctl boot $udid 2>/dev/null || true
  xcrun simctl bootstatus $udid -b >/dev/null
  if [[ $kind == ios ]]; then
    app=$IOS_APP; bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' $app/Info.plist)
    xcrun simctl ui $udid appearance dark
    xcrun simctl status_bar $udid override --time 9:41 --batteryState charged --batteryLevel 100 \
      --cellularBars 4 --wifiBars 3 --dataNetwork wifi
  else
    # watchOS has no appearance or status bar override; the app is dark anyway.
    app=$WATCH_APP; bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' $app/Info.plist)
  fi
  xcrun simctl install $udid $app
  # The first launch after an install can land in a process the system
  # started without our arguments; run it once and throw it away.
  xcrun simctl launch $udid $bundle >/dev/null; sleep 4
  out=$HERE/sources/$device
  mkdir -p $out
  screen=()
  if [[ ${display:-} == inner ]]; then
    screen=(--display=$(xcrun simctl io $udid enumerate | python3 -c "
import re, sys
ports = [p for p in sys.stdin.read().split('Port:') if 'Display class: 0' in p]
size = lambda p: int(re.search(r'Default width: (\\d+)', p)[1]) * int(re.search(r'Default height: (\\d+)', p)[1])
print(re.search(r'UUID: (\\S+)', max(ports, key=size))[1])"))
  fi
  for item in ${=scenes}; do
    scene=${item%%:*}; wait=${item##*:}
    xcrun simctl terminate $udid $bundle >/dev/null 2>&1 || true
    xcrun simctl launch $udid $bundle -StoreScreens $scene >/dev/null
    sleep $wait
    xcrun simctl io $udid screenshot $screen $out/$scene.png >/dev/null 2>&1
    echo "$device/$scene.png"
  done
  xcrun simctl terminate $udid $bundle >/dev/null 2>&1 || true
done
