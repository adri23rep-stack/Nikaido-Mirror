# Dependencias de la primera prueba

- Apple Mobile Device Support en Windows: proporciona el servicio usbmux de Apple.
  Instalarlo desde software oficial de Apple. Confirmar que el servicio reconoce
  el iPhone antes de culpar al encoder.
- libusbmuxd/iproxy: https://github.com/libimobiledevice/libusbmuxd
  Compilar siguiendo las instrucciones oficiales para Windows, o usar un paquete
  cuya procedencia puedas verificar. Colocar EXE y DLL asociadas junto al receptor.
  `iproxy --help` debe mostrar `-l` y `-s`. No se incluye binario no verificado.
- mpv para Windows: https://mpv.io/installation/
  Colocar `mpv.exe` y sus archivos de distribución junto al receptor. Esta prueba
  pide D3D11VA; comprobar el registro y el panel I para saber qué decoder usó
  realmente. Una opción pedida no demuestra aceleración activa.
- Desarrollo Windows: Python 3.12 y PyInstaller 6.16.0.
- Desarrollo iOS: Xcode 27, SDK iOS 27, XcodeGen.

Nikaido Mirror tiene licencia MIT. iproxy es GPL-2.0-or-later; libusbmuxd LGPL;
mpv y FFmpeg dependen de las opciones de compilación de cada distribución.
Si se empaquetan binarios de terceros en una release, incluir sus avisos,
licencias y el código fuente correspondiente según sus condiciones. El paquete
actual no redistribuye esos binarios ni los controladores propietarios de Apple.
