import Foundation
import CoreVideo

func make(_ width: Int, _ height: Int, _ format: OSType) -> CVPixelBuffer {
    var pixel: CVPixelBuffer?
    precondition(CVPixelBufferCreate(nil, width, height, format, nil, &pixel) == kCVReturnSuccess)
    return pixel!
}
func fillOrCheck(_ pixel: CVPixelBuffer, check: Bool) {
    precondition(CVPixelBufferLockBaseAddress(pixel, []) == kCVReturnSuccess)
    defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
    if CVPixelBufferGetPlaneCount(pixel) == 0 {
        let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
        let bytes: [UInt8] = [23, 78, 143, 255]
        for y in 0..<CVPixelBufferGetHeight(pixel) {
            for x in 0..<CVPixelBufferGetWidth(pixel) {
                for channel in 0..<4 {
                    let offset = y * CVPixelBufferGetBytesPerRow(pixel) + x * 4 + channel
                    if check { precondition(abs(Int(base[offset]) - Int(bytes[channel])) <= 1) }
                    else { base[offset] = bytes[channel] }
                }
            }
        }
    } else {
        for plane in 0..<2 {
            let base = CVPixelBufferGetBaseAddressOfPlane(pixel, plane)!.assumingMemoryBound(to: UInt8.self)
            let channels = plane == 0 ? 1 : 2
            for y in 0..<CVPixelBufferGetHeightOfPlane(pixel, plane) {
                for x in 0..<CVPixelBufferGetWidthOfPlane(pixel, plane) * channels {
                    let value: UInt8 = plane == 0 ? 100 : (x % 2 == 0 ? 90 : 170)
                    let offset = y * CVPixelBufferGetBytesPerRowOfPlane(pixel, plane) + x
                    if check { precondition(abs(Int(base[offset]) - Int(value)) <= 1) }
                    else { base[offset] = value }
                }
            }
        }
    }
}
for format in [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
               kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] {
    for dimensions in [(18, 10, 8, 4), (10, 18, 4, 8)] {
        let source = make(dimensions.0, dimensions.1, format)
        let target = make(dimensions.2, dimensions.3, format)
        fillOrCheck(source, check: false)
        try PixelScaler.resize(source, into: target)
        fillOrCheck(target, check: true)
    }
}
do {
    try PixelScaler.resize(make(8, 8, kCVPixelFormatType_32BGRA),
                           into: make(4, 4, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))
    fatalError("Format mismatch must fail")
} catch { }
precondition(!PixelScaler.supports(kCVPixelFormatType_32ARGB))
var thermal = ThermalPolicy()
precondition(thermal.target(thermal: 0, now: 0).fps == 60)
precondition(thermal.target(thermal: 2, now: 1).fps == 30)
precondition(thermal.target(thermal: 0, now: 30.9).fps == 30)
precondition(thermal.target(thermal: 1, now: 31).fps == 60)
let critical = thermal.target(thermal: 3, now: 32)
precondition(critical.fps == 15 && critical.longEdge == 960 && critical.shortEdge == 540)
precondition(thermal.target(thermal: 1, now: 61).fps == 30)
precondition(thermal.target(thermal: 0, now: 62).longEdge == 1280)
print("CPU scaler: BGRA, NV12 full/video range, portrait/landscape, strides, format rejection; thermal hysteresis passed")
