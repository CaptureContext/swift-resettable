// swift-tools-version: 6.0

import PackageDescription

let package = Package(
	name: "swift-resettable",
	platforms: [
		.macOS(.v10_15),
		.macCatalyst(.v13),
		.iOS(.v13),
		.tvOS(.v13),
		.watchOS(.v6)
	],
	products: [
		.library(
			name: "Resettable",
			targets: ["Resettable"]
		),
		.library(
			name: "_ResettableDebugging",
			targets: ["_ResettableDebugging"]
		)
	],
	dependencies: [
		.package(
			url: "https://github.com/capturecontext/swift-keypaths-extensions.git",
			.upToNextMinor(from: "0.1.5")
		),
		.package(
			url: "https://github.com/pointfreeco/swift-custom-dump",
			.upToNextMajor(from: "1.0.0")
		),
	],
	targets: [
		.target(
			name: "Resettable",
			dependencies: [
				.product(
					name: "KeyPathsExtensions",
					package: "swift-keypaths-extensions"
				),
			]
		),
		.target(
			name: "_ResettableDebugging",
			dependencies: [
				.target(name: "Resettable"),
				.product(
					name: "CustomDump",
					package: "swift-custom-dump"
				),
			]
		),
		.testTarget(
			name: "ResettableTests",
			dependencies: [
				.target(name: "_ResettableDebugging"),
			]
		),
	],
	swiftLanguageModes: [.v6]
)
