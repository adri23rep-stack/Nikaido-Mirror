"""USB video probe: bounded source, mpv hardware player, reconnect, CSV telemetry."""
import argparse
import csv
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time
from protocol import read_frame_details, DIAGNOSTIC_FIELDS
from player import PersistentPlayer, PlayerClosed, stop_process

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
              '--demuxer-lavf-o=probesize=32,analyzeduration=0',
              '--cache=no', '--audio=no', '--keep-open=no', '--input-terminal=no',
              '--input-default-bindings=yes', '--osd-level=1']
    if gaming:
        result += ['--profile=low-latency', '--untimed', '--vd-lavc-threads=1']
    else:
        result += ['--correct-pts=no', '--container-fps-override=60']
    return result + ['-']

def receive_frame(sock, player, clock=time.monotonic, notify=print):
    started = clock()
    announced = False
    def idle():
        nonlocal announced
        player.check()
        if not announced:
            notify('Sin vídeo del iPhone; manteniendo la ventana abierta...')
            announced = True
        if clock() - started >= 30:
            raise TimeoutError('30 s sin un fotograma completo; reconectando USB')
    # read_exact retains partial headers/payloads across socket idle timeouts.
    return read_frame_details(sock, on_idle=idle)


def run(args):
    iproxy, mpv = tool('iproxy'), tool('mpv')
    proxy = None
    print('Nikaido Mirror 0.1.4 · USB solamente · audio pendiente')
    print('F: pantalla completa | I: estadísticas mpv | Q: salir del reproductor')
    print('FPS RX = recibidos, NO presentados. Retraso total: pendiente de medición óptica.')
    logdir = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'NikaidoMirror' / 'logs'
    logdir.mkdir(parents=True, exist_ok=True)
    path = logdir / (time.strftime('%Y%m%d-%H%M%S') + '.csv')
    print('Registro:', path)
    player = PersistentPlayer(player_args(mpv, not args.quality), logdir / f'mpv-{path.stem}.log')
    decoder_restarts = 0
    try:
        with path.open('w', newline='', encoding='utf-8') as output:
            log = csv.writer(output)
            log.writerow(['session', 'host_rx_monotonic_ns', 'source_sequence', 'source_capture_us',
                          'encoder_us', 'bytes', 'source_frames_skipped', *DIAGNOSTIC_FIELDS])
            session = 0
            while True:
                try:
                    player.check()
                except PlayerClosed as error:
                    print(error); return
                if proxy is None or proxy.poll() is not None:
                    command = [iproxy, '-l', '-s', '127.0.0.1']
                    if args.udid:
                        command += ['-u', args.udid]
                    proxy = subprocess.Popen(command + ['27183:27183'])
                try:
                    with socket.create_connection(('127.0.0.1', 27183), timeout=3) as sock:
                        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                        sock.settimeout(1)
                        session += 1
                        last = None
                        count = skipped = 0
                        maxima = {}
                        start = time.monotonic()
                        # Preserve the same decoder/window when USB pauses or reconnects.
                        frame = receive_frame(sock, player)
                        player.start()
                        while True:
                            seq, source_us, enc_us, payload, details = frame
                            for key, value in {"encoder_us": enc_us, **details}.items():
                                if key.endswith("_us"):
                                    maxima[key] = max(maxima.get(key, 0), value)
                            now = time.monotonic_ns()
                            gap = max(0, seq - last - 1) if last is not None else 0
                            last = seq
                            skipped += gap
                            player.write(payload)
                            sock.sendall(b'A')
                            log.writerow([session, now, seq, source_us, enc_us, len(payload), gap,
                                          *(details.get(key, "") for key in DIAGNOSTIC_FIELDS)])
                            count += 1
                            elapsed = time.monotonic() - start
                            if elapsed >= 1:
                                print(f'FPS RX {count / elapsed:.1f} | encoder máx {maxima["encoder_us"] / 1000:.1f} ms | '
                                      f'omitidos origen {skipped} | retraso total: sin medir')
                                if details:
                                    state = {0: 'app', 1: 'inactiva/barra', 2: 'fondo'}.get(details['app_state'], '?')
                                    thermal = {0: 'normal', 1: 'moderado', 2: 'alto', 3: 'crítico'}.get(details['thermal_state'], '?')
                                    print(f'  {state} | térmico {thermal} | máximos ventana ms: '
                                          f'cola {maxima["queue_us"]/1000:.1f} · '
                                          f'imagen {maxima["prepare_us"]/1000:.1f} · '
                                          f'callback {maxima["callback_queue_us"]/1000:.1f} · '
                                          f'USB+ACK previo {maxima["previous_ack_us"]/1000:.1f} · '
                                          f'trabajo iPhone {maxima["source_work_us"]/1000:.1f}')
                                output.flush(); count = 0; maxima.clear(); start = time.monotonic()
                            frame = receive_frame(sock, player)
                except PlayerClosed as error:
                    print(error)
                    return
                except (OSError, EOFError, ValueError) as error:
                    print(f'Esperando iPhone / reconexión: {error}')
                    if player.killed_for_stall:
                        decoder_restarts += 1
                        player.close()
                        if decoder_restarts > 3:
                            print('El reproductor se bloqueó repetidamente. Revisa el registro de mpv.')
                            return
                    else:
                        try:
                            player.check()
                        except PlayerClosed as closed:
                            print(closed); return
                time.sleep(1)
    finally:
        player.close()
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
