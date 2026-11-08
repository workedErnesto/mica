// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "mica", platforms: [.macOS("15.4")], products: [.executable(name: "mica", targets: ["MicaApp"])], targets: [.target(name: "MicaCore"), .executableTarget(name: "MicaApp", dependencies: ["MicaCore"]), .testTarget(name: "MicaCoreTests", dependencies: ["MicaCore"])], swiftLanguageModes: [.v5])
