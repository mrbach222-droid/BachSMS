import Foundation

/// Bounded, latest-only translation scheduling. Access only from the extension's serial queue.
struct TranslationPolicy {
    private(set) var busy = false
    private(set) var requests = 0
    private(set) var lastSucceeded = ""
    private(set) var pending = ""
    private(set) var nextAllowed: TimeInterval = 0
    private(set) var lastSubmittedAt: TimeInterval = 0
    private var failures = 0
    let interval: TimeInterval
    let limit: Int

    init(interval: TimeInterval, limit: Int) {
        self.interval = max(2, interval)
        self.limit = max(1, limit)
    }
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    mutating func offer(_ text: String) {
        // A single newest candidate replaces the old pending text; no growing queue.
        pending = String(Self.normalized(text).prefix(900))
    }
    mutating func take(now: TimeInterval) -> String? {
        guard !busy, requests < limit, now >= nextAllowed,
              !pending.isEmpty, pending != lastSucceeded else { return nil }
        busy = true
        requests += 1
        lastSubmittedAt = now
        nextAllowed = now + interval
        let text = pending
        pending = ""
        return text
    }
    mutating func complete(text: String, success: Bool, now: TimeInterval,
                           retryAfter: TimeInterval? = nil) {
        busy = false
        if success {
            lastSucceeded = text
            failures = 0
        } else {
            failures += 1
            nextAllowed = now + max(interval, retryAfter ?? min(60, pow(2, Double(failures))))
            if pending.isEmpty { pending = text }
        }
    }
    mutating func discardPending() { pending = "" }
    var reachedLimit: Bool { requests >= limit }
}
