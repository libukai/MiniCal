// swift-tools-version: 6.0
import PackageDescription
let package = Package(
 name: "MiniCal",
 platforms: [.macOS(.v14)],
 products: [.executable(name: "MiniCal", targets: ["MiniCal"]), .executable(name: "MiniCalWidget", targets: ["MiniCalWidget"])],
 targets: [
  .target(name: "MiniCalCore", resources: [.process("Resources")]),
  .target(name: "MiniCalData", dependencies: ["MiniCalCore"]),
  .executableTarget(name: "MiniCal", dependencies: ["MiniCalCore", "MiniCalData"], resources: [.process("Resources")]),
  .executableTarget(name: "MiniCalWidget", dependencies: ["MiniCalCore"], path: "WidgetExtension", swiftSettings: [.unsafeFlags(["-application-extension"])], linkerSettings: [.unsafeFlags(["-Xlinker", "-application_extension", "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
  .testTarget(name: "MiniCalCoreTests", dependencies: ["MiniCalCore"]),
  .testTarget(name: "MiniCalDataTests", dependencies: ["MiniCalData"]),
  .testTarget(name: "MiniCalTests", dependencies: ["MiniCal"])
 ],
 swiftLanguageModes: [.v5]
)
