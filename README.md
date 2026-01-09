# swift-resettable

[![SwiftPM 6.2](https://img.shields.io/badge/Swift-6.2_|_5.10-ED523F.svg?style=flat)](https://swift.org/download/) ![Platforms](https://img.shields.io/badge/Platforms-iOS_13_|_macOS_10.15_|_tvOS_14_|_watchOS_7-ED523F.svg?style=flat) [![@capture_context](https://img.shields.io/badge/contact-@capture__context-1DA1F2.svg?style=flat&logo=twitter)](https://twitter.com/capture_context) 

Swift undo-redo manager

## Table of contents

- [Motivation](#motivation)
- [The Problem](#the-problem)
- [Usage](#usage)
- [Installation](#installation)
- [License](#license)

## Motivation

Undo and redo are common requirements in interactive applications, especially when working with mutable state that evolves over time.

While Swift makes it easy to mutate values, it does not provide a built-in mechanism to track changes or revert them in a structured way. As a result, undo / redo logic is often implemented manually, tightly coupled to application logic, or handled externally.

`swift-resettable` aims to provide a lightweight, opt-in mechanism for recording value changes and navigating their history.

## The Problem

Consider a mutable value that changes over time:

```swift
struct State {
 var value: Int = 0
}

var state = State()
state.value = 1
state.value *= 10
state.value += 1
```

Once these changes are applied, there is no straightforward way to revert to a previous state without manually storing snapshots or writing custom undo logic.

This quickly becomes error-prone as state grows more complex or mutations become more frequent.

## Usage

Mark a value as resettable to enable undo / redo functionality.

```swift
struct State {
  var value: Int = 0
}

@Resettable
let state = State()
```

Any subsequent mutations are recorded automatically:

```swift
state.value = 1   // value == 1
state.value *= 10 // value == 10
state.undo()      // value == 1
state.value += 1  // value == 2
state.undo()      // value == 1
state.redo()      // value == 2
```

Undo and redo operate on recorded value states, allowing you to navigate mutation history without manual bookkeeping.

## Installation

### Basic

You can add Resettable to an Xcode project by adding it as a package dependency.

1. From the **File** menu, select **Swift Packages › Add Package Dependency…**
2. Enter [`"https://github.com/capturecontext/swift-resettable.git"`](https://github.com/capturecontext/swift-resettable.git) into the package repository URL text field
3. Choose products you need to link them to your project.

### Recommended

If you use SwiftPM for your project, you can add Resettable to your package file.

```swift
.package(
  url: "https://github.com/capturecontext/swift-resettable.git", 
  .upToNextMinor(from: "0.1.0")
)
```

Do not forget about target dependencies:

```swift
.product(
  name: "Resettable", 
  package: "swift-resettable"
)
```

## License

This library is released under the MIT license. See [LICENCE](LICENCE) for details.
