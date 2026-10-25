// Queue-confined. Immediate load reduction, 30 seconds of cooling before restoration.
struct ThermalPolicy {
    private var lastHot = -Double.infinity
    mutating func target(thermal: Int, now: Double) -> (longEdge: Int, shortEdge: Int, fps: Int) {
        if thermal >= 2 { lastHot = now }
        if thermal >= 3 { return (960, 540, 15) }
        if now - lastHot < 30 { return (960, 540, 30) }
        return (1280, 720, 60)
    }
}
