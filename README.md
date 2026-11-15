<p align="center">
<img src="./Documentation/logo.svg" width="340" />
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.4+-F05138?logo=swift&logoColor=white" alt="Swift 6.4+"></a>
  <a href="https://swift.org/package-manager"><img src="https://img.shields.io/badge/SPM-compatible-4BC51D?logo=swift&logoColor=white" alt="SPM Compatible"></a>
  <a href="https://github.com/vapor/vapor"><img src="https://img.shields.io/badge/Vapor-5-6DBEEB?logo=vapor&logoColor=white" alt="Vapor 5"></a>
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/License-EUPL--1.2-blue.svg" alt="License: EUPL-1.2"></a>
</p>

## Introduction

`vapor-events` is an event system for Vapor. Events dispatch locally by
default and can be broadcast to other application instances. On the Vapor 4
line, listeners can also be handled by queued jobs.

## Installation

Add the package to your Vapor project's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "5.0.0-beta.4"),
    .package(url: "https://github.com/studio-falkland/vapor-events", branch: "vapor5"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "Vapor", package: "vapor"),
        .product(name: "VaporEvents", package: "vapor-events"),
    ]),
]
```

`VaporEvents` includes the core event bus and the Vapor adapter. Add a
transport product when you need cross-instance broadcasting:

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

Create an `Events` holder in `configure`, register it with the application
lifecycle, and pass it to the controllers that need it:

```swift
let events = Events()
app.addLifecycleHandler(events)
try await routes(app, events: events)
```

Register listeners in `configure`:

```swift
await events.bus.listen(SendReceipt(mailer: app.mailer))
```

Dispatch from a route:

```swift
try await events.bus.dispatch(OrderShipped(orderID: id))
```

Stream events as an `AsyncSequence`:

```swift
let stream = await events.bus.stream(OrderShipped.self)
for await event in stream {
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

events.broadcast.use(.postgres(configuration: .init(/* … */)))
```

With `VaporEventsValkey`:

```swift
import VaporEventsValkey

events.broadcast.use(.valkey(client: client))
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
await events.bus.listen(SendReceipt(mailer: app.mailer))
```

On the Vapor 4 line, the adapter registers the listener with `app.queues` and
enqueues it on dispatch. On the Vapor 5 line, [vapor/queues](https://github.com/vapor/queues)
has no release yet, so queued listeners require a custom `EventEnqueuing`
passed to `Events`:

```swift
let events = Events(enqueuing: MyEnqueuing())
```

## Testing

Use the fake dispatcher to record events without running listeners:

```swift
let fake = FakeEventDispatcher()

await fake.dispatch(OrderShipped(orderID: id))
let dispatched = await fake.dispatched(OrderShipped.self)
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
