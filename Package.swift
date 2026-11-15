// swift-tools-version: 6.2
import PackageDescription

// gaea-plugin-locate: Qwen3-VL-4B (Apache-2.0) as a Gaea plugin on MES Image 0.1's image.locate: a picture and a prompt
// in, boxes out. One worker executable built on GaeaPluginKit over mlx-locate-swift, packaged as a signed .gaeaplugin
// by scripts/build-plugin.sh.
//
// locate-inproc is not part of the plugin: it runs the same package in-process through MLXServeEngine, with the same
// dependency resolution, lane configuration and request, as the reference a run through Gaea is compared against.
//
// GAEA_PLUGIN_KIT_PATH points the kit at a local checkout while you work on both.
let kitPath = Context.environment["GAEA_PLUGIN_KIT_PATH"]

let package = Package(
    name: "gaea-plugin-locate",
    platforms: [.macOS(.v26)], // mlx-engine-swift's MLXToolKit requires macOS 26
    dependencies: [
        kitPath.map { .package(path: $0) }
            ?? .package(url: "https://github.com/xocialize-code/gaea-plugin-kit.git", from: "0.15.0"),
        .package(url: "https://github.com/xocialize/mlx-locate-swift.git", exact: "0.1.0"),
        // Exactly the engine GaeaPluginKit 0.15.0 and Gaea 1.9.0 are on (contract 1.65.0). A later 0.x could add fields
        // to the worker's memory report that GPP v1's closed schema doesn't carry, or a contract Gaea can't decode.
        .package(url: "https://github.com/xocialize/mlx-engine-swift.git", exact: "0.80.0"),
        // The fleet's mlx-swift fork, as mlx-engine-swift takes it: 0.32.4 is upstream 0.32.3 plus the
        // _updateInternal leak fix (ml-explore/mlx-swift#501; AB-D-0208).
        .package(url: "https://github.com/xocialize/mlx-swift", exact: "0.32.4"),
    ],
    targets: [
        .target(
            name: "LocatePlugin",
            dependencies: [
                .product(name: "GaeaPluginKit", package: "gaea-plugin-kit"),
                .product(name: "MLXLocate", package: "mlx-locate-swift"),
                .product(name: "MLXToolKit", package: "mlx-engine-swift"),
            ]
        ),
        .executableTarget(
            name: "gaea-locate-worker",
            dependencies: [
                "LocatePlugin",
                .product(name: "GaeaPluginKit", package: "gaea-plugin-kit"),
            ]
        ),
        .executableTarget(
            name: "locate-inproc",
            dependencies: [
                "LocatePlugin",
                .product(name: "MLXLocate", package: "mlx-locate-swift"),
                .product(name: "MLXToolKit", package: "mlx-engine-swift"),
                .product(name: "MLXServeCore", package: "mlx-engine-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LocatePluginTests",
            dependencies: ["LocatePlugin", .product(name: "GaeaPluginKit", package: "gaea-plugin-kit"),
                           .product(name: "GaeaProtocol", package: "gaea-plugin-kit"), .product(name: "MLXToolKit", package: "mlx-engine-swift")]
        ),
    ]
)
