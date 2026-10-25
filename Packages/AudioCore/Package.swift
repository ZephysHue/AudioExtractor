// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AudioCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "AudioCore", targets: ["AudioCore"])
    ],
    targets: [
        // LAME 3.99.5 MP3 encoder (LGPL-2.0), encoder only, built from source.
        .target(
            name: "CLame",
            path: "Sources/CLame",
            exclude: ["LICENSE-LGPL.txt"],
            publicHeadersPath: "include",
            cSettings: [
                .define("HAVE_CONFIG_H"),
                .headerSearchPath("."),
            ]
        ),
        .target(
            name: "AudioCore",
            dependencies: ["CLame"],
            path: "Sources/AudioCore"
        ),
    ]
)
