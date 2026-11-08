/// Marks a listener that runs as a queued job.
///
/// The listener's ``EventListener/handle(_:)`` is the job body. The Vapor
/// adapter registers the listener with `app.queues` and enqueues it on
/// dispatch, so `handle` runs on a queue worker instead of during dispatch.
public protocol ShouldQueue: EventListener {}
