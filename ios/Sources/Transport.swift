import Foundation
import Darwin

// Loopback only: USB forwarding must reach this socket; Wi-Fi cannot connect.
// Physical validation is required on the target iOS release.
final class Transport {
    private var listener: Int32 = -1
    private var client: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "mirror.usb")
    private let lock = NSLock()
    var connected: Bool { lock.lock(); defer { lock.unlock() }; return client >= 0 }
    var report: ((String) -> Void)?
    func start() throws {
        guard listener < 0 else { return }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError() }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(27183).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 1) == 0 else { Darwin.close(fd); throw posixError() }
        fcntl(fd, F_SETFL, O_NONBLOCK)
        listener = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let incoming = Darwin.accept(fd, nil, nil)
            guard incoming >= 0 else { return }
            self.lock.lock()
            guard self.client < 0 else { self.lock.unlock(); Darwin.close(incoming); return }
            self.client = incoming
            self.lock.unlock()
            var yes: Int32 = 1
            setsockopt(incoming, SOL_SOCKET, SO_NOSIGPIPE, &yes, 4)
            setsockopt(incoming, IPPROTO_TCP, TCP_NODELAY, &yes, 4)
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(incoming, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(incoming, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            self.report?("USB conectado · iniciando video")
        }
        source.setCancelHandler { Darwin.close(fd) }
        self.source = source
        source.resume()
    }
    // ACK after receiver pipe write bounds application buffering. NOT display latency.
    func send(_ data: Data, completion: @escaping (Bool) -> Void) {
        queue.async {
            self.lock.lock(); let fd = self.client; self.lock.unlock()
            guard fd >= 0 else { completion(false); return }
            var ok = true
            data.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                    if count <= 0 { ok = false; break }
                    offset += count
                }
            }
            var ack: UInt8 = 0
            if ok { ok = recv(fd, &ack, 1, 0) == 1 && ack == 0x41 }
            if !ok {
                self.lock.lock()
                if self.client == fd { self.client = -1; Darwin.close(fd) }
                self.lock.unlock()
                self.report?("USB desconectado · esperando reconexión")
            }
            completion(ok)
        }
    }
    func stop() {
        source?.cancel(); source = nil; listener = -1
        lock.lock()
        if client >= 0 { shutdown(client, SHUT_RDWR) }
        lock.unlock()
        queue.async {
            self.lock.lock(); defer { self.lock.unlock() }
            if self.client >= 0 { Darwin.close(self.client); self.client = -1 }
        }
    }
    private func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
