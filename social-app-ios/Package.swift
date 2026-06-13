// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SocialApp",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SocialApp", targets: ["SocialApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SocialApp",
            dependencies: [
                "matrix_sdk_ffiFFI",
                "matrix_sdkFFI",
                "matrix_sdk_baseFFI",
                "matrix_sdk_commonFFI",
                "matrix_sdk_cryptoFFI",
                "matrix_sdk_uiFFI"
            ],
            path: "SocialApp"
        ),
        .target(name: "matrix_sdk_ffiFFI", path: "MatrixFFI/matrix_sdk_ffi"),
        .target(name: "matrix_sdkFFI", path: "MatrixFFI/matrix_sdk"),
        .target(name: "matrix_sdk_baseFFI", path: "MatrixFFI/matrix_sdk_base"),
        .target(name: "matrix_sdk_commonFFI", path: "MatrixFFI/matrix_sdk_common"),
        .target(name: "matrix_sdk_cryptoFFI", path: "MatrixFFI/matrix_sdk_crypto"),
        .target(name: "matrix_sdk_uiFFI", path: "MatrixFFI/matrix_sdk_ui")
    ]
)