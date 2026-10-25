# Etapas funcionales

1. **Sonda USB/captura** (implementada, compilación y prueba física pendientes).
   Ver pantalla completa y juegos en Windows; medir antes de optimizar.
2. **Cerrar fallos y lograr primera versión jugable**. Rotación, pacing, buffers,
   recuperación, FPS presentados, medición óptica repetible. Integrar y empaquetar
   dependencias verificadas con sus licencias. No confundir EXE con instalador.
3. **Audio de juego**. Investigar salida .audio disponible del SDK, capturar con
   timestamps, transporte separado o multiplexado, reproducción WASAPI y ajuste
   gradual de reloj. Medir sincronización A/V y latencia. Sin micrófono por defecto.
4. **720p/60 sostenido y 1080p/60 opcional**. Comparar resolución efectiva, bitrate,
   batería, temperatura, encoder y decoder. No prometer FPS que captura no entrega.
5. **Reproductor integrado**. Ventana, fullscreen, escalado, perfiles Gaming/calidad,
   FPS captura/recepción/presentación, descartes por etapa, retraso estimado con
   incertidumbre; nunca llamar al RTT «latencia total».

No empezar un rediseño visual antes de completar 1 y 2.
