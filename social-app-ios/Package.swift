// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SocialApp",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SocialApp", targets: ["SocialApp"])
    ],
    dependencies: [
        // matrix-rust-sdk FFI bindings
        // .package(path: "../matrix-rust-sdk")
    ],
    targets: [
        .target(
            name: "SocialApp",
            path: "SocialApp"
        )
    ]
)