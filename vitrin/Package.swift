// swift-tools-version:5.10
// Çekirdek mantık (kaynaklar, filtreler, yapay zekâ) arayüzden bağımsızdır ve
// `swift test` ile macOS ya da Linux'ta test edilebilir. Uygulamanın kendisi
// XcodeGen (project.yml) ile oluşturulan Xcode projesinden derlenir.
import PackageDescription

let package = Package(
    name: "VitrinCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    targets: [
        .target(name: "VitrinCore", path: "Vitrin/Core"),
        .testTarget(name: "VitrinCoreTests", dependencies: ["VitrinCore"], path: "Tests/VitrinCoreTests"),
    ]
)
