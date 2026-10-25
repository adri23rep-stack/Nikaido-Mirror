# Investigación — 24 octubre 2026

## Fuentes primarias comprobadas

- Apple, captura iOS 27 y modo de segundo plano:
  https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios
- Apple, ScreenCaptureKit:
  https://developer.apple.com/documentation/screencapturekit
- Apple, requisito de encoder por hardware:
  https://developer.apple.com/documentation/videotoolbox/kvtvideoencoderspecification_requirehardwareacceleratedvideoencoder
- libusbmuxd y servicio Apple para Windows:
  https://github.com/libimobiledevice/libusbmuxd
- Opciones iproxy, USB local y bind:
  https://github.com/libimobiledevice/libusbmuxd/blob/master/docs/iproxy.1
- Runner ARM Xcode 27 disponible:
  https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/
- mpv y parámetros de decodificación:
  https://mpv.io/manual/stable/

## Decisiones y límites

ScreenCaptureKit permite selección de pantalla completa y background mediante
`screen-capture` según Apple. Eso no demuestra que cada juego entregue imagen y
60 FPS en el iPhone objetivo. No se presupone compatibilidad de contenido protegido.
No usamos ReplayKit como sustituto silencioso ni inventamos extensiones.

iproxy reenvía conexiones a un puerto del dispositivo. La app abre un socket
127.0.0.1:27183 para excluir clientes Wi-Fi. Debe probarse que usbmux de iOS 27
pueda alcanzar ese listener mientras la app captura en segundo plano. Si no,
primero registrar el fallo; no abrir 0.0.0.0 como parche sin autenticar clientes.
No se requiere jailbreak por diseño; esto debe confirmarse con dispositivo real.

VideoToolbox exige hardware y falla si no puede usarlo. mpv solicita D3D11VA;
se debe verificar su selección efectiva. Escalado mediante Core Image antes del
encoder, sin B-frames. Un solo cuadro pendiente y ACK limitan acumulación en la
app, pero añaden una vuelta de transporte: medir antes de sustituir por ventana
limitada. Los buffers internos de mpv, el sistema y la pantalla siguen existiendo.

El monitor de 165 Hz no convierte una captura de 60 FPS en 165 FPS. Lightning,
la temperatura, juego, captura, encoder y presentación tienen que medirse juntos.
