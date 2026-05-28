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
        // The passport NFC chip reader is an optional capability; integrators
        // that don't need NFC can disable the `nfc` step in the server-side
        // flow definition and the SDK will skip every NFC code path.
        .package(url: "https://github.com/AndyQ/NFCPassportReader.git", branch: "main")
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
