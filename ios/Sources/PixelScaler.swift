import Foundation
import CoreVideo
import Accelerate

// CPU-only resize. Never submits app-owned Metal/Core Image work in background.
// BGRA channel order is preserved because ARGB8888 scales all four channels equally.
enum PixelScaler {
    static func supports(_ format: OSType) -> Bool {
        format == kCVPixelFormatType_32BGRA ||
        format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
        format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    }
    static func resize(_ source: CVPixelBuffer, into destination: CVPixelBuffer) throws {
        let format = CVPixelBufferGetPixelFormatType(source)
        guard supports(format), CVPixelBufferGetPixelFormatType(destination) == format else {
            throw failure(Int(format), "Formato de captura no compatible con escalado CPU")
        }
        let sourceLock = CVPixelBufferLockBaseAddress(source, .readOnly)
        guard sourceLock == kCVReturnSuccess else { throw failure(Int(sourceLock), "Bloquear imagen origen") }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        let targetLock = CVPixelBufferLockBaseAddress(destination, [])
        guard targetLock == kCVReturnSuccess else { throw failure(Int(targetLock), "Bloquear imagen destino") }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }
        let flags = vImage_Flags(kvImageNoFlags)
        if format == kCVPixelFormatType_32BGRA {
            guard let src = CVPixelBufferGetBaseAddress(source), let dst = CVPixelBufferGetBaseAddress(destination) else {
                throw failure(-1, "Imagen BGRA sin memoria")
            }
            var input = vImage_Buffer(data: src, height: vImagePixelCount(CVPixelBufferGetHeight(source)),
                width: vImagePixelCount(CVPixelBufferGetWidth(source)), rowBytes: CVPixelBufferGetBytesPerRow(source))
            var output = vImage_Buffer(data: dst, height: vImagePixelCount(CVPixelBufferGetHeight(destination)),
                width: vImagePixelCount(CVPixelBufferGetWidth(destination)), rowBytes: CVPixelBufferGetBytesPerRow(destination))
            let status = vImageScale_ARGB8888(&input, &output, nil, flags)
            guard status == kvImageNoError else { throw failure(Int(status), "Escalar BGRA") }
        } else {
            guard CVPixelBufferGetPlaneCount(source) == 2, CVPixelBufferGetPlaneCount(destination) == 2 else {
                throw failure(-2, "Se requieren dos planos NV12")
            }
            for plane in 0..<2 {
                guard let src = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let dst = CVPixelBufferGetBaseAddressOfPlane(destination, plane) else {
                    throw failure(-3, "Plano NV12 sin memoria")
                }
                var input = vImage_Buffer(data: src, height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(source, plane)),
                    width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(source, plane)), rowBytes: CVPixelBufferGetBytesPerRowOfPlane(source, plane))
                var output = vImage_Buffer(data: dst, height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(destination, plane)),
                    width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(destination, plane)), rowBytes: CVPixelBufferGetBytesPerRowOfPlane(destination, plane))
                let status = plane == 0 ? vImageScale_Planar8(&input, &output, nil, flags)
                                        : vImageScale_CbCr8(&input, &output, nil, flags)
                guard status == kvImageNoError else { throw failure(Int(status), "Escalar NV12") }
            }
        }
        CVBufferPropagateAttachments(source, destination)
    }
    private static func failure(_ code: Int, _ text: String) -> NSError {
        NSError(domain: "Nikaido.PixelScaler", code: code, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
