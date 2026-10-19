#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build/verification .build/cache/clang
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
swiftc Sources/YotoPlaylistStudio/Models.swift Sources/YotoPlaylistStudio/Suggestions.swift Sources/YotoPlaylistStudio/ArtGenerator.swift Sources/YotoPlaylistStudio/CommunityIcons.swift Sources/YotoPlaylistStudio/AudioImport.swift Verification/Checks.swift -o .build/verification/checks
.build/verification/checks
