import SwiftUI

@main
struct MirrorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var capture = Capture()
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 24) {
                Text("Nikaido Mirror").font(.largeTitle.bold())
                Text("USB · prueba 0.1.4").foregroundStyle(.secondary)
                Text(capture.status).multilineTextAlignment(.center)
                Button("Compartir pantalla completa") { capture.start() }
                    .buttonStyle(.borderedProminent).disabled(capture.active)
                Button("Detener") { capture.stop() }.disabled(!capture.active)
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
                    Text(String(format: "%09.0f", ProcessInfo.processInfo.systemUptime * 1000))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                }
                Text("Mide el retraso filmando este contador y su copia en Windows juntos. Después abre tu juego.\nAudio pendiente en esta prueba.")
                    .font(.footnote).multilineTextAlignment(.center)
            }.padding()
                .onChange(of: scenePhase, initial: true) { _, phase in
                    capture.setActivity(phase == .active ? 0 : (phase == .inactive ? 1 : 2))
                }
        }
    }
}
