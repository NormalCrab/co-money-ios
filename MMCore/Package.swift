// swift-tools-version: 6.0
//
// MMCore：app 裡不碰畫面的部分（docs/ios-design.md §5，在 django-mm repo）。
// 不依賴 UIKit / SwiftUI / Vision，所以可以在 Linux 上編譯與跑測試：
//   swift test --package-path MMCore

import PackageDescription

let package = Package(
    name: "MMCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MMCore", targets: ["MMCore"]),
    ],
    targets: [
        .target(name: "MMCore"),
        .testTarget(name: "MMCoreTests", dependencies: ["MMCore"]),
    ]
)
