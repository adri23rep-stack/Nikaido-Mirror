import Foundation
import CoreGraphics
import VideoToolbox

private final class FrameContext {
    let sequence: UInt64
    let capturedAt: UInt64
    let startedAt: UInt64
    let generation: UInt64
    let queuedUs: UInt64
    let preparedUs: UInt64
    let activity: UInt64
    init(sequence: UInt64, capturedAt: UInt64, generation: UInt64,
         queuedUs: UInt64, preparedUs: UInt64, activity: UInt64) {
        self.sequence = sequence; self.capturedAt = capturedAt
        self.startedAt = Pipeline.micros(); self.generation = generation
        self.queuedUs = queuedUs; self.preparedUs = preparedUs; self.activity = activity
    }
}

final class Pipeline {
    var report: ((String) -> Void)?
    var failed: ((String) -> Void)?
    private var recovery = EncoderRecovery()
    private let transport = Transport()
    private var thermalPolicy = ThermalPolicy()
    private var pixelFormat: OSType = 0
    private var targetFPS = 60
    private let queue = DispatchQueue(label: "mirror.encode", qos: .userInteractive)
    private let lock = NSLock()
    private var busy = false
    private var running = false
    private var activity: UInt64 = 0
    private var previousAckUs: UInt64 = 0
    func setActivity(_ value: UInt64) { lock.lock(); activity = value; lock.unlock() }
    private var session: VTCompressionSession?
    private var size = CGSize.zero
    private var pool: CVPixelBufferPool?
    private var captureCount: UInt64 = 0
    private var lastPTS = -Double.infinity
    private var forceKey = true
    private var generation: UInt64 = 0
    static func micros() -> UInt64 { UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000) }
    func start() {
        queue.async { self.recovery = EncoderRecovery(); self.previousAckUs = 0; self.thermalPolicy = ThermalPolicy() }
        lock.lock(); running = true; lock.unlock()
        transport.report = { [weak self] in self?.report?($0) }
        do { try transport.start() } catch { report?("Puerto USB: \(error)") }
    }
    func stop() {
        lock.lock(); running = false; lock.unlock()
        transport.stop()
        queue.async {
            self.resetEncoder()
            self.releaseGate()
        }
    }
    // Only called on the encoding queue; stale callbacks cannot release a new frame's gate.
    private func resetEncoder() {
        generation &+= 1
        if let session { VTCompressionSessionInvalidate(session) }
        session = nil; pool = nil; size = .zero; pixelFormat = 0
        forceKey = true; lastPTS = -.infinity
    }
    private func encoderFailed(_ error: Error, stage: String) {
        let code = (error as NSError).code
        let detail = (error as NSError).domain == "Nikaido.PixelScaler" ? " · \(error.localizedDescription)" : ""
        resetEncoder()
        let retry = recovery.retry(now: ProcessInfo.processInfo.systemUptime)
        if retry {
            report?("Encoder \(stage): \(code)\(detail) · recuperando sesión (\(recovery.attempts)/3)")
        } else {
            lock.lock(); running = false; lock.unlock()
            failed?("Encoder \(stage): \(code)\(detail) · recuperación agotada. Pulsa Compartir para reintentar.")
        }
        releaseGate()
    }
    private func releaseGate() { lock.lock(); busy = false; lock.unlock() }
    func accept(_ pixel: CVPixelBuffer, pts: CMTime) {
        lock.lock()
        captureCount &+= 1
        let number = captureCount
        let currentActivity = activity
        guard running, !busy, transport.connected else { lock.unlock(); return }
        busy = true
        lock.unlock()
        let receivedAt = Self.micros()
        queue.async {
            let processingAt = Self.micros()
            self.lock.lock(); let running = self.running; self.lock.unlock()
            guard running else { self.releaseGate(); return }
            guard self.recovery.ready(now: ProcessInfo.processInfo.systemUptime) else {
                self.releaseGate(); return
            }
            var stage = "configuración"
            let time = CMTimeGetSeconds(pts)
            guard time.isFinite else { self.releaseGate(); return }
            let profile = self.thermalPolicy.target(thermal: ProcessInfo.processInfo.thermalState.rawValue,
                                                   now: ProcessInfo.processInfo.systemUptime)
            // Admission ceiling; capture FPS remains controlled by iOS.
            if time >= self.lastPTS && time - self.lastPTS < 1.0 / Double(profile.fps) - 0.001 {
                self.releaseGate(); return
            }
            self.lastPTS = time
            do {
                let w = CVPixelBufferGetWidth(pixel), h = CVPixelBufferGetHeight(pixel)
                let scale = min(1.0, min(Double(profile.longEdge) / Double(max(w, h)), Double(profile.shortEdge) / Double(min(w, h))))
                let width = max(2, Int(Double(w) * scale) / 2 * 2)
                let height = max(2, Int(Double(h) * scale) / 2 * 2)
                let format = CVPixelBufferGetPixelFormatType(pixel)
                guard PixelScaler.supports(format) else {
                    throw NSError(domain: "Nikaido.PixelScaler", code: Int(format),
                                  userInfo: [NSLocalizedDescriptionKey: "Formato de captura no compatible"])
                }
                if self.size != CGSize(width: width, height: height) || self.pixelFormat != format || self.targetFPS != profile.fps {
                    try self.configure(width: width, height: height, format: format, fps: profile.fps)
                }
                guard let session = self.session, let pool = self.pool else { throw self.error(-1) }
                stage = "preparación de imagen"
                var target: CVPixelBuffer?
                try self.check(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &target))
                guard let target else { throw self.error(-2) }
                try PixelScaler.resize(pixel, into: target)
                let frame = FrameContext(sequence: number, capturedAt: receivedAt, generation: self.generation,
                    queuedUs: processingAt - receivedAt, preparedUs: Self.micros() - processingAt,
                    activity: currentActivity)
                let handle = Unmanaged.passRetained(frame).toOpaque()
                let properties = self.forceKey ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
                self.forceKey = false
                stage = "codificación"
                let result = VTCompressionSessionEncodeFrame(session, imageBuffer: target,
                    presentationTimeStamp: pts, duration: .invalid, frameProperties: properties,
                    sourceFrameRefcon: handle, infoFlagsOut: nil)
                if result != noErr { Unmanaged<FrameContext>.fromOpaque(handle).release() }
                try self.check(result)
            } catch {
                self.encoderFailed(error, stage: stage)
            }
        }
    }
    private func check(_ code: OSStatus) throws { if code != noErr { throw error(code) } }
    private func error(_ code: OSStatus) -> NSError { NSError(domain: "Nikaido.VideoToolbox", code: Int(code)) }
    private func configure(width: Int, height: Int, format: OSType, fps: Int) throws {
        resetEncoder()
        let callback: VTCompressionOutputCallback = { ref, frameRef, status, flags, buffer in
            let callbackAt = Pipeline.micros()
            guard let frameRef else { return }
            let frame = Unmanaged<FrameContext>.fromOpaque(frameRef).takeRetainedValue()
            guard let ref else { return }
            let owner = Unmanaged<Pipeline>.fromOpaque(ref).takeUnretainedValue()
            owner.queue.async {
                owner.encoded(buffer, status: status, flags: flags, frame: frame, callbackAt: callbackAt)
            }
        }
        func create(lowLatency: Bool) -> OSStatus {
            var specification: [CFString: Any] = [
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true
            ]
            if lowLatency { specification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = true }
            return VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
                codecType: kCMVideoCodecType_H264, encoderSpecification: specification as CFDictionary,
                imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: callback,
                refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &session)
        }
        var lowLatency = true
        var result = create(lowLatency: true)
        if result != noErr {
            // Older/unsupported encoders retain the existing hardware path, never software fallback.
            print("Low latency encoder unavailable: \(result); trying standard hardware encoder")
            if let session { VTCompressionSessionInvalidate(session) }
            session = nil
            lowLatency = false
            result = create(lowLatency: false)
        }
        try check(result)
        guard let session else { throw error(-3) }
        for (key, value) in [
            (kVTCompressionPropertyKey_RealTime, kCFBooleanTrue as CFTypeRef),
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse as CFTypeRef),
            (kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel as CFTypeRef),
            (kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: fps < 60 ? 4_000_000 : 8_000_000)),
            (kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: fps))
        ] { try check(VTSessionSetProperty(session, key: key, value: value)) }
        // Optional speed hints must not break devices that reject them.
        let speedStatus = VTSessionSetProperty(session,
            key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanTrue)
        if speedStatus != noErr { print("Encoding speed hint unsupported: \(speedStatus)") }
        if !lowLatency {
            try check(VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                                          value: NSNumber(value: 60)))
        }
        try check(VTCompressionSessionPrepareToEncodeFrames(session))
        let attributes: [CFString: Any] = [kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: format,
            kCVPixelBufferIOSurfacePropertiesKey: [:]]
        try check(CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool))
        size = CGSize(width: width, height: height); forceKey = true
        pixelFormat = format; targetFPS = fps
        report?("CPU escala · \(width)×\(height) / \(fps) FPS · H.264 \(lowLatency ? "baja latencia" : "modo compatible")")
    }
    private func encoded(_ buffer: CMSampleBuffer?, status: OSStatus, flags: VTEncodeInfoFlags, frame: FrameContext, callbackAt: UInt64) {
        guard frame.generation == generation else { return }
        guard status == noErr else {
            encoderFailed(error(status), stage: "callback"); return
        }
        guard !flags.contains(.frameDropped), let buffer,
              let block = CMSampleBufferGetDataBuffer(buffer),
              let format = CMSampleBufferGetFormatDescription(buffer) else {
            forceKey = true; releaseGate(); return
        }
        let encodedAt = Self.micros()
        var payload = Data()
        var headerLength: Int32 = 0
        var parameterCount = 0
        guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0,
            parameterSetPointerOut: nil, parameterSetSizeOut: nil,
            parameterSetCountOut: &parameterCount, nalUnitHeaderLengthOut: &headerLength) == noErr,
            headerLength == 4 else { forceKey = true; releaseGate(); return }
        // Repeat SPS/PPS on every access unit, so a reconnected receiver can find format.
        for index in 0..<parameterCount {
            var pointer: UnsafePointer<UInt8>?
            var length = 0
            if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index,
                parameterSetPointerOut: &pointer, parameterSetSizeOut: &length,
                parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr, let pointer {
                payload.append(contentsOf: [0, 0, 0, 1]); payload.append(pointer, count: length)
            }
        }
        var bytes = Data(count: CMBlockBufferGetDataLength(block))
        let copied = bytes.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
        }
        guard copied == noErr else { forceKey = true; releaseGate(); return }
        var offset = 0
        while offset + 4 <= bytes.count {
            let length = bytes[offset..<offset+4].reduce(0) { ($0 << 8) | Int($1) }
            offset += 4
            guard length > 0, length <= bytes.count - offset else { forceKey = true; releaseGate(); return }
            payload.append(contentsOf: [0, 0, 0, 1]); payload.append(bytes[offset..<offset+length]); offset += length
        }
        guard offset == bytes.count, payload.count <= 8 * 1024 * 1024 else { forceKey = true; releaseGate(); return }
        var packet = Data("NM02".utf8)
        packet.appendBE(UInt32(payload.count)); packet.appendBE(frame.sequence)
        packet.appendBE(frame.capturedAt); packet.appendBE(callbackAt - frame.startedAt)
        packet.appendBE(frame.queuedUs); packet.appendBE(frame.preparedUs)
        packet.appendBE(encodedAt - callbackAt); packet.appendBE(previousAckUs)
        packet.appendBE(encodedAt - frame.capturedAt); packet.appendBE(frame.activity)
        packet.appendBE(UInt64(ProcessInfo.processInfo.thermalState.rawValue))
        packet.append(payload)
        let currentGeneration = generation
        let sendingAt = Self.micros()
        transport.send(packet) { ok in
            let acknowledgedAt = Self.micros()
            self.queue.async {
                guard currentGeneration == self.generation else { return }
                self.previousAckUs = acknowledgedAt - sendingAt
                if !ok { self.forceKey = true }
                self.releaseGate()
            }
        }
    }
}

private extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var number = value.bigEndian
        Swift.withUnsafeBytes(of: &number) { append(contentsOf: $0) }
    }
}
