#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build/verification .build/cache/clang
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
swiftc Sources/YotoPlaylistStudio/Models.swift Sources/YotoPlaylistStudio/Suggestions.swift Sources/YotoPlaylistStudio/ArtGenerator.swift Sources/YotoPlaylistStudio/CommunityIcons.swift Sources/YotoPlaylistStudio/PublicAudio.swift Sources/YotoPlaylistStudio/AudioImport.swift Verification/Checks.swift -o .build/verification/checks
.build/verification/checks

swiftc Sources/YotoPlaylistStudio/Models.swift Sources/YotoPlaylistStudio/PublicAudio.swift Sources/YotoPlaylistStudio/AudioImport.swift Sources/YotoPlaylistStudio/YotoService.swift Sources/YotoPlaylistStudio/ParallelAudio.swift Verification/ServiceChecks.swift -o .build/verification/service-checks
.build/verification/service-checks

swiftc Sources/YotoPlaylistStudio/ParallelAudio.swift Verification/ParallelChecks.swift -o .build/verification/parallel-checks
.build/verification/parallel-checks
