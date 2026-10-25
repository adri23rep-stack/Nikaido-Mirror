# NM01 — video probe

TCP sobre usbmux/iproxy, puerto 27183, solo loopback en ambos extremos.
Un receptor por sesión, sin descubrimiento LAN. No hay audio ni autenticación
adicional en esta etapa local; procesos del mismo dispositivo pueden acceder.
No exponer el puerto a la red.

Cabecera de 32 bytes, big endian:

| Offset | Tipo | Significado |
|---|---|---|
| 0 | 4 bytes | ASCII NM01 |
| 4 | uint32 | bytes de payload; 1..8388608 |
| 8 | uint64 | número de callback de captura |
| 16 | uint64 | reloj monotónico iPhone, al admitir cuadro, microsegundos |
| 24 | uint64 | duración de codificación, microsegundos |

Payload: una unidad H.264 Annex B, SPS/PPS repetidos y NALs del cuadro.
Cliente devuelve byte ASCII A tras escribir la unidad al reproductor. El emisor
espera hasta dos segundos y cierra al fallar, solicitando IDR al reconectar.
Los descartes son anteriores a codificación para no romper referencias H.264.
Nuevo tamaño reinicia encoder e IDR. Los saltos de secuencia no miden pérdida USB.
La primera IDR de un emisor ya activo puede llegar tras el intervalo de keyframe.
Receptor valida la longitud antes de reservar memoria y admite fragmentación TCP.
