// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceNoiseRepair",
    platforms: [.iOS(.v16)],
    products: [.library(name: "RNNoiseC", targets: ["RNNoiseC"])],
    targets: [.target(name: "RNNoiseC", path: "Sources/RNNoiseC",
        sources: ["src/denoise.c", "src/rnn.c", "src/rnn_data.c", "src/pitch.c", "src/kiss_fft.c", "src/celt_lpc.c"],
        publicHeadersPath: "include",
        cSettings: [.headerSearchPath("src"), .define("RNNOISE_BUILD")],
        linkerSettings: [.linkedLibrary("m")])],
    cLanguageStandard: .c99
)
