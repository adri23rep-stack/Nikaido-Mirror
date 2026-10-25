# Prueba física pendiente

No rellenar resultados por inferencia. Hardware objetivo: iPhone 14 Pro iOS 27,
Windows 11, RTX 3060, monitor 165 Hz, Lightning a USB.

1. Guardar versión exacta iOS, Xcode, commit, driver NVIDIA y modelo de cable.
2. Compilar los tres jobs. La compilación no sustituye esta prueba.
3. Instalar app firmada, conectar por cable, confiar y apagar Wi-Fi en ambos.
4. Iniciar captura completa y receptor. Debe verse el contador en Windows.
5. Abrir juego y mantener movimiento cinco minutos. Probar retrato/paisaje.
   Registrar si la app se suspende, si hay negro, estiramiento o giro incorrecto.
6. Revisar log de mpv para decoder efectivo D3D11VA. Guardar CSV de receptor.
7. Con otro teléfono/cámara, filmar contador iPhone y copia en monitor juntos,
   idealmente a 240 FPS. Restar números visibles del mismo fotograma. Tomar
   al menos 30 muestras, reportar mediana y p95. Registrar exposición, Hz y
   precisión del contador; no dar más precisión que la captura permite.
8. Repetir con interacción del juego (flash/cambio visible), Gaming y --quality.
   El contador mide display-to-display, no toda la latencia desde pulsar un botón.
9. Desconectar y reconectar cinco veces. El receptor debe reabrir la transmisión
   si la captura continúa. Si iOS detiene la captura, pedir permiso de nuevo.
10. Sesión de 15 minutos: temperaturas observadas/estado térmico, FPS, errores,
    memoria. No pasar a 1080p hasta cerrar fallos de esta etapa.

| Métrica | Resultado |
|---|---|
| Captura real de juego en background | PENDIENTE |
| USB sin Wi-Fi | PENDIENTE |
| FPS RX / FPS presentados | PENDIENTE / PENDIENTE |
| Encoder / decoder hardware | PENDIENTE / PENDIENTE |
| Retraso mediana / p95 | PENDIENTE / PENDIENTE |
| Reconexiones correctas / 5 | PENDIENTE |
| Rotación y proporción | PENDIENTE |

Criterio de primera versión jugable: imagen del juego real por USB, fluidez
estable observada, retraso óptico documentado y aceptable para el juego elegido,
sin crecimiento continuo de cola ni necesidad de reiniciar al desconectar.
La aceptación no se decide con el contador de FPS RX solamente.
