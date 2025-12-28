# swift-resettable

[![CI](https://github.com/CaptureContext/swift-resettable/actions/workflows/ci.yml/badge.svg)](https://github.com/CaptureContext/swift-resettable/actions/workflows/ci.yml) [![SwiftPM 6.2](https://img.shields.io/badge/swiftpm-6.0-ED523F.svg?style=flat)](https://swift.org/download/) ![Platforms](https://img.shields.io/badge/Platforms-iOS_13_|_macOS_10.15_|_tvOS_14_|_watchOS_7-ED523F.svg?style=flat) [![@capture_context](https://img.shields.io/badge/contact-@capture__context-1DA1F2.svg?style=flat&logo=twitter)](https://twitter.com/capture_context) 

Swift undo-redo manager

- [Documentation](https://swiftpackageindex.com/CaptureContext/swift-resettables/0.0.1/documentation/Resettable)
- [Contents](#contents)
  - [Usage](#usage)
- [Installation](#installation)
  - [Basic](#basic)
  - [Recommended](#recommended)
- [Licence](#licence)

## Contents

### Usage

```swift
struct State {
  var value: Int = 0
}

@Resettable
let state = State()
state.value = 1   // value == 1
state.value *= 10 // value == 10
state.undo()      // value == 1
state.value += 1  // value == 2
state.undo()      // value == 1
state.redo()      // value == 2
```

## Installation

### Basic

You can add Resettable to an Xcode project by adding it as a package dependency.

1. From the **File** menu, select **Swift Packages › Add Package Dependency…**
2. Enter [`"https://github.com/capturecontext/swift-resettable.git"`](https://github.com/capturecontext/swift-resettable.git) into the package repository URL text field
3. Choose products you need to link them to your project.

### Recommended

If you use SwiftPM for your project, you can add StandardExtensions to your package file.

```swift
.package(
  url: "https://github.com/capturecontext/swift-resettable.git", 
  .upToNextMinor(from: "0.0.1")
)
```

Do not forget about target dependencies:

```swift
.product(
  name: "Resettable", 
  package: "swift-resettable"
)
```

```swift
.product(
  name: "ResettableMacros", 
  package: "swift-resettable"
)
```



## License

This library is released under the MIT license. See [LICENCE](LICENCE) for details.
