// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "YotoPlaylistStudio", platforms: [.macOS(.v13)], products: [.executable(name: "YotoPlaylistStudio", targets: ["YotoPlaylistStudio"])], targets: [.executableTarget(name: "YotoPlaylistStudio"), .testTarget(name: "YotoPlaylistStudioTests", dependencies: ["YotoPlaylistStudio"])])
