#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build/verification .build/cache/clang
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
swiftc Sources/YotoPlaylistStudio/Models.swift Sources/YotoPlaylistStudio/Suggestions.swift Sources/YotoPlaylistStudio/ArtGenerator.swift Sources/YotoPlaylistStudio/CommunityIcons.swift Sources/YotoPlaylistStudio/PublicAudio.swift Sources/YotoPlaylistStudio/AudioImport.swift Verification/Checks.swift -o .build/verification/checks
.build/verification/checks

swiftc Sources/YotoPlaylistStudio/Models.swift Sources/YotoPlaylistStudio/PublicAudio.swift Sources/YotoPlaylistStudio/AudioImport.swift Sources/YotoPlaylistStudio/PlaylistOrder.swift Sources/YotoPlaylistStudio/YotoSession.swift Sources/YotoPlaylistStudio/YotoService.swift Sources/YotoPlaylistStudio/ParallelAudio.swift Verification/ServiceChecks.swift -o .build/verification/service-checks
.build/verification/service-checks

swiftc Sources/YotoPlaylistStudio/ParallelAudio.swift Verification/ParallelChecks.swift -o .build/verification/parallel-checks
.build/verification/parallel-checks

swiftc Sources/YotoPlaylistStudio/Models.swift Sources/YotoPlaylistStudio/PublicAudio.swift Sources/YotoPlaylistStudio/AudioImport.swift Verification/TrimChecks.swift -o .build/verification/trim-checks
.build/verification/trim-checks

swiftc Sources/YotoPlaylistStudio/Models.swift Sources/YotoPlaylistStudio/PublicAudio.swift Sources/YotoPlaylistStudio/AudioImport.swift Sources/YotoPlaylistStudio/PlaylistOrder.swift Sources/YotoPlaylistStudio/YotoSession.swift Sources/YotoPlaylistStudio/YotoService.swift Sources/YotoPlaylistStudio/PlaylistMove.swift Verification/MoveChecks.swift -o .build/verification/move-checks
.build/verification/move-checks

swiftc Sources/YotoPlaylistStudio/Models.swift Sources/YotoPlaylistStudio/PublicAudio.swift Sources/YotoPlaylistStudio/AudioImport.swift Verification/LocalAudioChecks.swift -o .build/verification/local-audio-checks
.build/verification/local-audio-checks

swiftc Sources/YotoPlaylistStudio/Models.swift Sources/YotoPlaylistStudio/PublicAudio.swift Sources/YotoPlaylistStudio/AudioImport.swift Sources/YotoPlaylistStudio/PlaylistOrder.swift Sources/YotoPlaylistStudio/YotoSession.swift Sources/YotoPlaylistStudio/YotoService.swift Verification/OrderChecks.swift -o .build/verification/order-checks
.build/verification/order-checks

swiftc Sources/YotoPlaylistStudio/Models.swift Sources/YotoPlaylistStudio/YotoSession.swift Verification/SessionChecks.swift -o .build/verification/session-checks
.build/verification/session-checks

swiftc Sources/YotoPlaylistStudio/Models.swift Sources/YotoPlaylistStudio/PublicAudio.swift Sources/YotoPlaylistStudio/PlaylistDuplicates.swift Verification/DuplicateChecks.swift -o .build/verification/duplicate-checks
.build/verification/duplicate-checks
