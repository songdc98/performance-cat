#!/usr/bin/env bash
set -euo pipefail

# Builds both language variants into dist/:
#   性能监测猫猫.app   (Chinese)
#   Performance Cat.app (English)
#
# Build only one: ./build.sh zh   or   ./build.sh en

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
mkdir -p "$BUILD"

# Generate the shared app icon once, from the cat artwork.
swift "$ROOT/scripts/make_icon.swift" "$BUILD/AppIcon.iconset" "$ROOT/assets/icon.png"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"

build_variant() {
  local appname="$1" plist="$2" swiftflag="$3"
  local app="$ROOT/dist/$appname.app"
  local contents="$app/Contents"
  local macos="$contents/MacOS"
  local resources="$contents/Resources"

  rm -rf "$app"
  mkdir -p "$macos" "$resources"

  # shellcheck disable=SC2086
  swiftc -O -whole-module-optimization $swiftflag \
    "$ROOT/Sources/PerformanceCat/main.swift" \
    -o "$macos/PerformanceCat" \
    -framework AppKit -framework IOKit

  cp "$ROOT/App/$plist" "$contents/Info.plist"
  cp "$BUILD/AppIcon.icns" "$resources/AppIcon.icns"

  # Bundle the macmon sensor helper so power/temp work with zero install.
  if [ -x "$ROOT/bin/macmon" ]; then
    cp "$ROOT/bin/macmon" "$resources/macmon"
    chmod +x "$resources/macmon"
  else
    echo "WARNING: bin/macmon not found; app will fall back to native-only mode"
  fi

  echo "Built: $app"
}

want="${1:-all}"
if [ "$want" = "zh" ] || [ "$want" = "all" ]; then
  build_variant "性能监测猫猫" "Info.zh.plist" ""
fi
if [ "$want" = "en" ] || [ "$want" = "all" ]; then
  build_variant "Performance Cat" "Info.en.plist" "-D ENGLISH"
fi
