# vapor-events — Agent Guide

## What this is

An event system for Vapor: local dispatch by default, optional cross-instance
broadcast, optional queued listeners.

## Architecture

- `VaporEventsCore` does not import Vapor.
- `VaporEvents` is the Vapor 4 adapter and re-exports the core.
- `Event` is a `Codable`, `Sendable` value type. `EventListener` handles one event type.
- `ShouldBroadcast` on the event publishes to an `EventBroadcaster`.
- `ShouldQueue` on the listener routes it to a queue instead of running inline.
- `ShouldQueue` wins over broadcast fan-out for that listener.
- Transports: `InProcess`, Postgres `LISTEN`/`NOTIFY`, Redis pub/sub.
- One channel per event type.
- `main` targets Vapor 4. A `vapor5` branch will target Vapor 5 (explicit DI,
  `Service`, streaming API).

## Development practices

1. **Validate with diagnostics, not builds.** Use the `diagnostics` tool after
   edits. Only build when you've confirmed all the implementation details with the user.
2. **Prefer built-in tools.** Use `read_file`, `grep`, `find_path`, `edit_file`,
   and `diagnostics` over shell commands.
3. **Reuse, don't reinvent.** Before writing a helper, check whether Vapor,
   Fluent, Queues, PostgresNIO, Redis, or the standard library already provides
   it.
4. **Plan, then wait.** Write an implementation plan and get an explicit
   go-ahead before writing code. Never implement without confirmation.
5. **Keep comments short.** Explain how the code flows, not why a decision was
   made.
6. **Keep this file current.** It is not static. When a new feature or piece of
   information conflicts with it, check with the user and update it.

## Commands

- `swift test` — run the suite.
- `swift build` — only when diagnostics and tests can't answer.
