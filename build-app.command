#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build/cache/clang .build/cache/swift
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/cache/swift"
swift build -c release --cache-path "$PWD/.build/cache/packages"
APP="$PWD/Yoto Playlist Studio.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/YotoPlaylistStudio "$APP/Contents/MacOS/YotoPlaylistStudio"
strip -S "$APP/Contents/MacOS/YotoPlaylistStudio"
mkdir -p "$APP/Contents/Resources"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
open "$APP"
