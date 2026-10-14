// swift-tools-version:5.9
import PackageDescription

// One app, two platforms: the shared code lives in Sources/Mochi, and each platform's own code in
// Sources/Mochi/Mac or Sources/Mochi/Windows (the other one is left out of the build).
#if os(Windows)
let targets: [Target] = [
    .executableTarget(
        name: "Mochi",
        dependencies: ["CDirect2D"],
        path: "Sources/Mochi",
        exclude: ["Mac"],
        linkerSettings: [
            .linkedLibrary("User32"), .linkedLibrary("Gdi32"), .linkedLibrary("Dwmapi"),
            .linkedLibrary("Shell32"), .linkedLibrary("Advapi32"), .linkedLibrary("Winmm"),
            .unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"]),
        ]
    ),
    // Direct2D and DirectWrite behind a small C interface.
    .target(
        name: "CDirect2D",
        path: "Sources/CDirect2D",
        linkerSettings: [.linkedLibrary("d2d1"), .linkedLibrary("dwrite"), .linkedLibrary("windowscodecs"), .linkedLibrary("Ole32")]
    ),
]
#else
let targets: [Target] = [
    .executableTarget(
        name: "Mochi",
        path: "Sources/Mochi",
        exclude: ["Windows"]
    ),
]
#endif

let package = Package(
    name: "Mochi",
    platforms: [.macOS(.v14)],
    targets: targets,
    cxxLanguageStandard: .cxx17
)
