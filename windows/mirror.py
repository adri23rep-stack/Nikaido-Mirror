"""USB video probe: bounded source, mpv hardware player, reconnect, CSV telemetry."""
import argparse
import csv
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import threading
import time
from protocol import read_frame

ROOT = Path(sys.executable if getattr(sys, 'frozen', False) else __file__).resolve().parent

def tool(name):
    local = ROOT / (name + '.exe')
    result = str(local) if local.is_file() else shutil.which(name)
    if not result:
        raise RuntimeError(f'Falta {name}.exe. Consulta README; colócalo junto a NikaidoMirror.exe.')
    return result

def player_args(mpv, gaming):
    result = [mpv, '--no-config', '--title=Nikaido Mirror · USB', '--hwdec=d3d11va',
              '--vo=gpu', '--gpu-api=d3d11', '--demuxer-lavf-format=h264',
              '--demuxer-lavf-o=probesize=32,analyzeduration=0', '--fps=60',
              '--cache=no', '--audio=no', '--keep-open=no', '--input-terminal=no',
              '--input-default-bindings=yes', '--osd-level=1']
    if gaming:
        result += ['--profile=low-latency', '--untimed', '--vd-lavc-threads=1']
    return result + ['-']

def stop_process(process):
    if process and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill(); process.wait()

def run(args):
    iproxy, mpv = tool('iproxy'), tool('mpv')
    proxy = None
    print('Nikaido Mirror 0.1 · USB solamente · audio pendiente')
    print('F: pantalla completa | I: estadísticas mpv | Q: salir del reproductor')
    print('FPS RX = recibidos, NO presentados. Retraso total: pendiente de medición óptica.')
    logdir = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'NikaidoMirror' / 'logs'
    logdir.mkdir(parents=True, exist_ok=True)
    path = logdir / (time.strftime('%Y%m%d-%H%M%S') + '.csv')
    print('Registro:', path)
    try:
        with path.open('w', newline='', encoding='utf-8') as output:
            log = csv.writer(output)
            log.writerow(['session', 'host_rx_monotonic_ns', 'source_sequence', 'source_capture_us',
                          'encoder_us', 'bytes', 'source_frames_skipped'])
            session = 0
            while True:
                if proxy is None or proxy.poll() is not None:
                    command = [iproxy, '-l', '-s', '127.0.0.1']
                    if args.udid:
                        command += ['-u', args.udid]
                    proxy = subprocess.Popen(command + ['27183:27183'])
                player = None
                try:
                    with socket.create_connection(('127.0.0.1', 27183), timeout=3) as sock:
                        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                        sock.settimeout(5)
                        session += 1
                        last = None
                        count = skipped = 0
                        start = time.monotonic()
                        # First complete frame validates USB before opening a player.
                        frame = read_frame(sock)
                        with (logdir / f'mpv-{session}-{path.stem}.log').open('w', encoding='utf-8') as playerlog:
                            player = subprocess.Popen(player_args(mpv, not args.quality), stdin=subprocess.PIPE,
                                                      stdout=playerlog, stderr=subprocess.STDOUT, bufsize=0)
                            # Close the socket promptly if the user closes mpv.
                            def watch(proc, connection):
                                proc.wait()
                                try:
                                    connection.shutdown(socket.SHUT_RDWR)
                                except OSError:
                                    pass
                            threading.Thread(target=watch, args=(player, sock), daemon=True).start()
                            while True:
                                seq, source_us, enc_us, payload = frame
                                now = time.monotonic_ns()
                                gap = max(0, seq - last - 1) if last is not None else 0
                                last = seq
                                skipped += gap
                                view = memoryview(payload)
                                while view:
                                    written = player.stdin.write(view)
                                    if not written:
                                        raise BrokenPipeError('mpv pipe closed')
                                    view = view[written:]
                                sock.sendall(b'A')
                                log.writerow([session, now, seq, source_us, enc_us, len(payload), gap])
                                count += 1
                                elapsed = time.monotonic() - start
                                if elapsed >= 1:
                                    print(f'FPS RX {count / elapsed:.1f} | encoder {enc_us / 1000:.1f} ms | '
                                          f'omitidos origen {skipped} | retraso total: sin medir')
                                    output.flush(); count = 0; start = time.monotonic()
                                frame = read_frame(sock)
                except (OSError, EOFError, ValueError) as error:
                    print(f'Esperando iPhone / reconexión: {error}')
                    if player is not None and player.poll() is not None:
                        if player.returncode != 0:
                            print('mpv falló; revisa su registro. No se ocultará con reintentos.')
                        return
                finally:
                    stop_process(player)
                time.sleep(1)
    finally:
        stop_process(proxy)

def main():
    parser = argparse.ArgumentParser(description='Nikaido Mirror USB probe')
    parser.add_argument('--udid', help='Selecciona el iPhone si hay varios conectados')
    parser.add_argument('--quality', action='store_true', help='Prueba con temporización normal; comparar con Gaming')
    args = parser.parse_args()
    try:
        run(args)
    except KeyboardInterrupt:
        print('\nDetenido.')
    except RuntimeError as error:
        print(error)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
