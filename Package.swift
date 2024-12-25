// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PerfectLDAP",
    products: [
        .library(
            name: "PerfectLDAP",
            targets: ["PerfectLDAP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jcombs-pointblue/Perfect-ICONV.git", from: "1.0.0"),
        .package(url: "https://github.com/PerfectlySoft/Perfect-libSASL.git", from: "1.0.0"),
        .package(url: "https://github.com/PerfectlySoft/Perfect-OpenLDAP.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "PerfectLDAP",
            dependencies: ["PerfectICONV"]),
        .testTarget(
            name: "PerfectLDAPTests",
            dependencies: ["PerfectLDAP"]),
    ]
)
