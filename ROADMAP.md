# vapor-events — Roadmap

This document describes what is done, what remains, and how to implement it.
Read `AGENTS.md` first for conventions and architecture.

## Current state

Done:

- `Event`, `EventListener`, `EventError`.
- `EventBus` protocol (including `receive`), `EventDispatcher` actor, and
  `stream()` backed by `Multicast`.
- `DispatchObserver` and the `EventObserving` observer seam.
- `Multicast`, `Cancellation`, and `ObserverSet` support types.
- `FakeEventDispatcher` and assertion helpers in `Testing/`.
- `ShouldBroadcast`, `EventEnvelope`, `EventTransportError`, `BroadcastDriver`,
  `BroadcastRelay`.
- `InProcessBroadcastDriver` and `PostgresBroadcastDriver` (both `Multicast`-backed;
  Postgres adds reconnect backoff, an 8 KB payload cap, and channel-name
  sanitization).
- `BroadcastDriverFactory` with `.postgres(client:)` and
  `.postgres(configuration:)`.
- Vapor 4 adapter: `Application.events`, `Request.events`, `app.broadcast.use(...)`,
  `BroadcastShutdown`.
- Logging: `BroadcastRelay` and `PostgresBroadcastDriver` log publish, receive,
  and reconnect failures through `swift-log`.
- Unit tests for dispatch, streams, observers, broadcasting, and the fake.
- Postgres integration test, gated on `POSTGRES_HOST`.

## Remaining work

### 1. `ShouldQueue` (highest priority)

Goal: listeners marked `ShouldQueue` run as queued jobs instead of inline.

Design:

- Core marker:
  ```swift
  public protocol ShouldQueue: EventListener {}
  ```
- New product `VaporEventsQueues` depending on `vapor/queues`.
- The queued listener is the job:
  ```swift
  public protocol QueuedEventListener: ShouldQueue, AsyncJob
  where Payload == EventType {}

  extension QueuedEventListener {
      public func dequeue(_ context: QueueContext, _ payload: EventType) async throws {
          try await self.handle(payload)
      }
  }
  ```
- The dispatcher must know whether a listener is queued. Options:
  - Add an `enqueue` closure to the registration, supplied by the queues
    product. `EventDispatcher.Registration` already carries a `handle` closure,
    so an `enqueue` sibling fits the existing shape.
  - Or add a `Queue` dependency to the dispatcher/relay.
- Precedence: `ShouldQueue` wins over broadcast fan-out. The origin enqueues one
  job; remote instances skip that listener.
- Register the listener with `app.queues.add(listener)`.
- Tests with `XCTQueues` / `AsyncTestQueuesDriver`.

Open questions:

- Should `ShouldQueue` live in the core (marker) or in `VaporEventsQueues`
  (with `AsyncJob`)?
- How is the queue injected: a `Queue` property, an `enqueue` closure, or a
  separate observer?

### 2. Redis transport

Goal: `RedisBroadcastDriver` using Redis pub/sub.

Design:

- New product `VaporEventsRedis` depending on `vapor/redis`.
- `publish<E>`: `PUBLISH` the JSON-encoded envelope on the event's channel.
- `subscribe<E>(to:)`: `SUBSCRIBE` the channel, yield envelopes.
- One `Multicast` per event type, same as the other drivers.
- Reconnect loop.
- Sanitize channel names.
- Integration tests gated on `REDIS_HOST`.

Verify the `vapor/redis` publish/subscribe API before implementing.

### 3. Broadcast configuration

Goal: per-event channels, payload, and conditional broadcasting.

Design:

```swift
public protocol ShouldBroadcast: Event {
    var broadcastChannels: [String] { get }
    var broadcastPayload: Data { get }
    var shouldBroadcast: Bool { get }
}

extension ShouldBroadcast {
    var broadcastChannels: [String] { [Self.name] }
    var broadcastPayload: Data { try! JSONEncoder().encode(self) }
    var shouldBroadcast: Bool { true }
}
```

This changes `BroadcastDriver.subscribe(to:)` and `BroadcastRelay`, which
currently assume one channel per event type. Consider deferring until the need
is concrete.

### 4. Default relay

Broadcasting is currently opt-in: `app.broadcast.use(...)` is required.

Options:

- Lazily create a default `InProcessBroadcastDriver` relay on first access.
- Keep it opt-in and document it.

### 5. Model events

Deliberately not shipped. Add a README recipe showing an `AsyncModelMiddleware`
that dispatches `ModelCreated<M>`, `ModelUpdated<M>`, etc.

### 6. Documentation and release

- README: full usage, broadcast setup, Postgres setup, testing, API tables.
- DocC: add a `Documentation.docc` catalog with articles.
- CI: add a Postgres service job for the integration test.
- Release: tag and submit to the Swift Package Index.

### 7. Vapor 5 branch

Deferred. The core is Vapor-free, so only the adapter changes:

- Explicit DI instead of `Application.storage`.
- `Service` conformance for the relay and drivers.
- Streaming response API.
- Swift 6.4 / macOS 26.

## Known rough edges

- `EventEnvelope.id` and `publishedAt` are unused. Use them for dedup/ordering
  or remove them.
- `EventBus.stream` returns a bare `AsyncStream` and drops the `Multicast`
  subscription's cancellation, so consumers cannot unsubscribe explicitly.
- The relay must be installed before listeners are registered:
  `EventDispatcher` notifies observers only on an event type's first
  registration.
- A throwing local listener suppresses the broadcast, because `dispatch`
  publishes only after local delivery succeeds.
- `Application.events` has a public setter; replacing the dispatcher after the
  relay is installed leaves the relay observing the old one.
- `PostgresBroadcastDriver.subscribe` has no shutdown guard; subscribing after
  `shutdown()` starts a new listener task.
- `EventTransportError.invalidEnvelope` is never thrown; Postgres logs and skips
  undecodable payloads.

## Conventions

See `AGENTS.md`. In short:

- Validate with `diagnostics`, not builds.
- Plan, then wait for an explicit go-ahead.
- Comment in blocks of 2–5 lines; type doc comments are descriptive.
- Prefer `FoundationEssentials` with a guarded import.
- Re-read files before editing; the user edits alongside you.
