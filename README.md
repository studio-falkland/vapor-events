<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift&logoColor=white" alt="Swift 6.0+"></a>
  <a href="https://swift.org/package-manager"><img src="https://img.shields.io/badge/SPM-compatible-4BC51D?logo=swift&logoColor=white" alt="SPM Compatible"></a>
  <a href="LICENSE.md"><img src="https://img.shields.io/github/license/studio-falkland/vapor-events" alt="License"></a>
</p>

## Introduction

`vapor-events` is an event system for Vapor. Events dispatch locally by
default, can be broadcast to other application instances, and can be handled by
queued listeners.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/studio-falkland/vapor-events", from: "0.1.0"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "VaporEvents", package: "vapor-events"),
    ]),
]
```

## Usage

The public API is being implemented. See `AGENTS.md` for the architecture and
the current implementation tier.

## Running Tests

```bash
swift test
```

## Authors

This library is developed by Lei Nelissen at Studio Falkland.

## License

Licensed under the **European Union Public Licence v. 1.2 (EUPL-1.2)**. See [`LICENSE.md`](LICENSE.md) for the full text.
