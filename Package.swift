// swift-tools-version: 5.9
import PackageDescription

// Пакет нужен ради `swift build`, `swift test` и работы в Xcode. Бандл
// приложения по-прежнему собирает build.sh: он берёт бинарник из .build,
// добавляет Info.plist, иконку и подпись.
let package = Package(
    name: "DaktRecorder",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DaktRecorder",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "DaktRecorderTests",
            dependencies: ["DaktRecorder"],
            path: "Tests"
        )
    ]
)
