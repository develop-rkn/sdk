// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FacedKYC",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "FacedKYC", targets: ["FacedKYC"])
    ],
    dependencies: [
        // Pinned to a tagged release so this package can itself be consumed
        // as a versioned dependency — SPM forbids a stable-versioned package
        // from depending on a branch-pinned one.
        .package(url: "https://github.com/AndyQ/NFCPassportReader.git", from: "2.3.0")
    ],
    targets: [
        .target(
            name: "FacedKYC",
            dependencies: [
                .product(name: "NFCPassportReader", package: "NFCPassportReader")
            ],
            path: "Sources/FacedKYC"
        ),
        .testTarget(
            name: "FacedKYCTests",
            dependencies: ["FacedKYC"],
            path: "Tests/FacedKYCTests"
        )
    ]
)
