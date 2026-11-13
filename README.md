<p align="center">
<img src="./Documentation/logo.svg" width="340" />
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift&logoColor=white" alt="Swift 6.0+"></a>
  <a href="https://swift.org/package-manager"><img src="https://img.shields.io/badge/SPM-compatible-4BC51D?logo=swift&logoColor=white" alt="SPM Compatible"></a>
  <a href="https://github.com/vapor/vapor"><img src="https://img.shields.io/badge/Vapor-4-6DBEEB?logo=vapor&logoColor=white" alt="Vapor 4"></a>
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/License-EUPL--1.2-blue.svg" alt="License: EUPL-1.2"></a>
</p>

## Introduction

`vapor-events` is an event system for Vapor. Events dispatch locally by
default, can be broadcast to other application instances, and can be handled by
queued listeners.

## Installation

Add the package to your Vapor project's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.122.3"),
    .package(url: "https://github.com/studio-falkland/vapor-events", from: "1.0.0"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "Vapor", package: "vapor"),
        .product(name: "VaporEvents", package: "vapor-events"),
    ]),
]
```

`VaporEvents` includes the core event bus, the Vapor adapter, and queued
listeners. Add a transport product when you need cross-instance broadcasting:

| Product | Transport |
|---|---|
| `VaporEventsPostgres` | Postgres `LISTEN`/`NOTIFY` |
| `VaporEventsValkey` | Valkey or Redis pub/sub |

## Usage

Define an event and a listener:

```swift
struct OrderShipped: Event {
    let orderID: UUID
}

struct SendReceipt: EventListener {
    let mailer: Mailer

    func handle(_ event: OrderShipped) async throws {
        try await self.mailer.sendReceipt(for: event.orderID)
    }
}
```

Register listeners in `configure`:

```swift
await app.events.listen(SendReceipt(mailer: app.mailer))
```

Dispatch from a route:

```swift
try await req.events.dispatch(OrderShipped(orderID: id))
```

Stream events as an `AsyncSequence`:

```swift
let events = await req.events.stream(OrderShipped.self)
for await event in events {
    // Consume the event.
}
```

## Broadcasting

Mark an event with `ShouldBroadcast` to publish it to other application
instances after local delivery succeeds:

```swift
struct OrderShipped: ShouldBroadcast {
    let orderID: UUID
}
```

Configure a driver in `configure`. With `VaporEventsPostgres`:

```swift
import VaporEventsPostgres

app.broadcast.use(.postgres(configuration: .init(/* … */)))
```

With `VaporEventsValkey`:

```swift
import VaporEventsValkey

app.broadcast.use(.valkey(client: client))
```

The Postgres factory creates and runs its own client for the application's
lifetime. The Valkey factory uses a client you own and run yourself. Postgres
uses a single `LISTEN`/`NOTIFY` channel for all event types, while Valkey uses
one channel per event type.

## Queued listeners

Mark a listener with `ShouldQueue` to run it as a queue job instead of inline
during dispatch:

```swift
struct SendReceipt: ShouldQueue {
    let mailer: Mailer

    func handle(_ event: OrderShipped) async throws {
        try await self.mailer.sendReceipt(for: event.orderID)
    }
}
```

Register it the same way:

```swift
await app.events.listen(SendReceipt(mailer: app.mailer))
```

The Vapor adapter registers the listener with `app.queues` and enqueues it on
dispatch. Queued listeners require [vapor/queues](https://github.com/vapor/queues),
which `VaporEvents` already depends on.

## Testing

Use the fake dispatcher to record events without running listeners:

```swift
let fake = FakeEventDispatcher()
app.events = fake

try await req.events.dispatch(OrderShipped(orderID: id))
let events = await fake.dispatched(OrderShipped.self)
```

The fake also provides `assertDispatched`, `assertNotDispatched`, and
`assertListening` helpers.

## Running Tests

```bash
swift test
```

## Authors

This library is developed by Lei Nelissen at Studio Falkland.

![Studio Falkland](./Documentation/falkland-logo-long-orange.svg)

## License

Licensed under the **European Union Public Licence v. 1.2 (EUPL-1.2)**. See [`LICENSE.md`](LICENSE.md) for the full text.
