// Queue-confined policy, with injected monotonic time for deterministic tests.
struct EncoderRecovery {
    private(set) var attempts = 0
    private var windowStart: Double?
    private var retryAt = -Double.infinity
    func ready(now: Double) -> Bool { now >= retryAt }
    mutating func retry(now: Double) -> Bool {
        if windowStart == nil || now - windowStart! >= 30 {
            windowStart = now
            attempts = 0
        }
        guard attempts < 3 else { return false }
        attempts += 1
        retryAt = now + 0.5
        return true
    }
}
