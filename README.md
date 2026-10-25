# Nikaido Mirror — 0.1.0 USB probe

Proyecto gratuito y abierto (MIT). Primera implementación experimental para
capturar iPhone → USB → ventana Windows. **No es todavía una versión verificada
ni una promesa de 60 FPS.** Audio, controles remotos y 1080p no están incluidos.

## Estado exacto de esta entrega

- Documentación oficial comprobada: ScreenCaptureKit iOS 27, captura completa,
  modo de fondo `screen-capture`, runner `xcode-27`, forwarding de iproxy.
- Implementados: app Swift, H.264 VideoToolbox que requiere hardware, servidor
  local, receptor Python/mpv, Gaming por defecto, reconexión, CSV, workflows.
- Pruebas locales: protocolo fragmentado, desconexión, límites, ACK sobre TCP.
- **Pendiente**: compilación Xcode/Windows, instalación firmada, USB físico,
  continuidad al abrir juegos, orientación, aceleración real del receptor,
  FPS sostenidos y medición óptica de retraso.
- No se generó IPA ni EXE en este entorno Linux. Los workflows los generan al
  ejecutarse en GitHub; un YAML preparado no significa una compilación aprobada.
- El repositorio remoto no pudo crearse: el conector no ofrece esa operación y
  el navegador no tiene sesión. El ZIP conserva `.git` con commits locales.

## Prueba prevista

1. Subir este repositorio a GitHub y revisar que los tres trabajos de Actions
   terminen correctamente. Descargar ambos artefactos.
2. Firmar e instalar la IPA en el iPhone mediante un método de instalación válido.
   La IPA de CI no está firmada y no se instala por sí sola. La continuidad en
   segundo plano debe probarse instalada normalmente; no se garantiza en contenedores.
3. Windows necesita Apple Mobile Device Support, `iproxy.exe`, `mpv.exe` y sus
   dependencias. Ver [DEPENDENCIES](docs/DEPENDENCIES.md). El EXE es el receptor,
   no incluye todavía instalador ni esas dependencias.
4. Conectar Lightning a USB, desbloquear y aceptar «Confiar» en el iPhone.
5. Abrir Nikaido Mirror en iPhone, pulsar **Compartir pantalla completa** y
   aceptar el selector de iOS. Abrir `NikaidoMirror.exe` en Windows.
6. Desactivar Wi-Fi en ambos equipos para la prueba USB. El receptor ejecuta
   `iproxy -l -s 127.0.0.1 27183:27183`; `-l` selecciona solo USB.
7. Ver el contador primero, medirlo y después abrir un juego. F alterna pantalla
   completa; redimensionar la ventana conserva la proporción. I muestra datos mpv.
8. Ctrl+C detiene el receptor y su iproxy. «Detener» termina la captura en iPhone.
   No se reanuda captura sin consentimiento si iOS la finaliza.

Con varios iPhones, usar `NikaidoMirror.exe --udid IDENTIFICADOR`.
`--quality` permite comparar la temporización normal de mpv con Gaming; en esta
etapa no cambia resolución/bitrate del emisor. El objetivo se encaja dentro de
1280×720 (o 720×1280), manteniendo proporción, sin estirar la pantalla del iPhone.
Un iPhone panorámico puede producir menos de 720 píxeles en el lado corto.

## Medición honesta

CSV en `%LOCALAPPDATA%\NikaidoMirror\logs`. FPS RX mide cuadros recibidos; los
saltos de secuencia incluyen los descartados antes del encoder y NO representan
paquetes USB perdidos. `encoder_us` mide desde después del escalado hasta la
salida del encoder; no incluye toda la captura. Los relojes de PC e iPhone no
se restan entre sí. **Retraso total: sin medir** hasta hacer la prueba óptica.
El ACK confirma escritura al pipe de mpv, no presentación en el monitor.

[Prueba física y medición](docs/VALIDATION.md) · [Etapas](docs/ROADMAP.md) ·
[Fuentes y decisiones](docs/RESEARCH.md) · [Protocolo](docs/PROTOCOL.md)

## Desarrollo

Pruebas: `python -m unittest discover -s tests -v`.
Receptor desde código: `python windows/mirror.py` (requiere mpv/iproxy).
App: `cd ios && xcodegen generate`; abrir proyecto con Xcode 27.
Se usa Swift 5 para no asumir aislamiento Swift 6 en callbacks del SDK nuevo.
