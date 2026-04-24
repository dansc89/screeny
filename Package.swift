// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Screeny",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Screeny", targets: ["Screeny"])
    ],
    targets: [
        .executableTarget(name: "Screeny")
    ]
)
