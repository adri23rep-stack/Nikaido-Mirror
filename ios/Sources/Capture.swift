import ScreenCaptureKit
import Combine
import CoreMedia

final class Capture: NSObject, ObservableObject, SCContentSharingPickerObserver, SCStreamDelegate, SCStreamOutput {
    @Published var status = "Conecta el cable y abre el receptor de Windows."
    @Published var active = false
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "mirror.capture", qos: .userInteractive)
    private let pipeline = Pipeline()
    private var generation = 0

    override init() {
        super.init()
        pipeline.failed = { [weak self] text in
            DispatchQueue.main.async {
                self?.stop()
                self?.status = text
            }
        }
        pipeline.report = { [weak self] text in
            DispatchQueue.main.async { self?.status = text }
        }
    }
    func setActivity(_ value: UInt64) { pipeline.setActivity(value) }
    func start() {
        active = true
        let picker = SCContentSharingPicker.shared
        picker.add(self)
        picker.isActive = true
        picker.present()
    }
    func stop() {
        generation += 1
        let old = stream
        stream = nil
        active = false
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
        Task { try? await old?.stopCapture() }
        queue.async { self.pipeline.stop() }
        status = "Detenido"
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async { self.stop() }
    }
    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async { self.stop(); self.status = error.localizedDescription }
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        DispatchQueue.main.async {
            self.generation += 1
            let generation = self.generation
            Task { @MainActor in
                do {
                    try await self.stream?.stopCapture()
                    guard self.generation == generation else { return }
                    let config = SCStreamConfiguration()
                    // iOS 27 API: request at most 60 FPS and the documented minimum queue depth.
                    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                    config.queueDepth = 3
                    let next = SCStream(filter: filter, configuration: config, delegate: self)
                    try next.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
                    self.stream = next
                    self.queue.async { self.pipeline.start() }
                    try await next.startCapture()
                    if self.generation != generation { try? await next.stopCapture(); return }
                    self.status = "Capturando · esperando receptor USB"
                } catch {
                    guard self.generation == generation else { return }
                    self.stop(); self.status = "Captura: \(error.localizedDescription)"
                }
            }
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            guard self.stream === stream else { return }
            self.stop(); self.status = error.localizedDescription
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferDataIsReady(sampleBuffer),
              let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        pipeline.accept(image, pts: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
