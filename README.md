# Nikaido Mirror — 0.1.3 USB probe

Proyecto gratuito y abierto (MIT). Primera implementación experimental para
capturar iPhone → USB → ventana Windows. **No es todavía una versión verificada
ni una promesa de 60 FPS.** Audio, controles remotos y 1080p no están incluidos.

## Prueba actual: lentitud en segundo plano

El usuario confirmó imagen por USB y recepción cercana a 60 FPS dentro de la
app. Al abrir notificaciones o salir de ella reportó lentitud y picos de hasta
399.9 ms en la métrica anterior del encoder. No se ha medido retraso óptico.

**Actualizar IPA y EXE juntos a 0.1.3.** Esta prueba solicita baja latencia en el
encoder, ajusta prioridad de las colas y añade mediciones por etapa. El EXE nuevo
acepta las IPA antiguas, pero el EXE antiguo no acepta el protocolo NM02 nuevo.
Mantener iproxy, mpv y controladores existentes. Ver [diagnóstico y prueba](docs/BACKGROUND.md).
No se considera corregida la lentitud hasta probar esta versión en el iPhone.

## Historial de la primera entrega 0.1.0

- Documentación oficial comprobada: ScreenCaptureKit iOS 27, captura completa,
  modo de fondo `screen-capture`, runner `xcode-27`, forwarding de iproxy.
- Implementados: app Swift, H.264 VideoToolbox que requiere hardware, servidor
  local, receptor Python/mpv, Gaming por defecto, reconexión, CSV, workflows.
- Pruebas locales: protocolo fragmentado, desconexión, límites, ACK sobre TCP.
- **Pendiente**: instalación firmada, USB físico,
  continuidad al abrir juegos, orientación, aceleración real del receptor,
  FPS sostenidos y medición óptica de retraso.
- **Compilación confirmada**: iOS con Xcode 27 e IPA sin firma; Windows x64 con
  EXE y prueba de arranque `--help`; 8 pruebas del protocolo aprobadas en Linux
  y Windows. Primera ejecución verificada:
  https://github.com/adri23rep-stack/Nikaido-Mirror/actions/runs/40167484364
- Código de esa compilación: `d7de98bca2831c6c580835fe17cff24337b14b01`.
  Los binarios son sondas de prueba, no una validación de captura física.
- El código y su historial ya están publicados en este repositorio.

## Prueba prevista

1. Abrir [Actions](https://github.com/adri23rep-stack/Nikaido-Mirror/actions),
   elegir una ejecución aprobada y descargar los artefactos
   `NikaidoMirror-iOS-unsigned` y `NikaidoMirror-Windows-x64`.
   Extraer ambos ZIP. El primero contiene la IPA; el segundo, el EXE.
   Descargar artefactos de Actions puede requerir iniciar sesión en GitHub.
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

## Continuar desde GitHub

```sh
git clone https://github.com/adri23rep-stack/Nikaido-Mirror.git
cd Nikaido-Mirror
```

Los archivos `history.bundle` de la entrega inicial son una copia del historial
local anterior a la publicación. Para nuevos cambios, usar este repositorio.

## Desarrollo

Pruebas: `python -m unittest discover -s tests -v`.
Receptor desde código: `python windows/mirror.py` (requiere mpv/iproxy).
App: `cd ios && xcodegen generate`; abrir proyecto con Xcode 27.
Se usa Swift 5 para no asumir aislamiento Swift 6 en callbacks del SDK nuevo.
