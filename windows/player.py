"""Keep one mpv window across USB reconnects; only watchdog an active pipe write."""
import subprocess
import threading
import time


class PlayerClosed(Exception):
    pass


def stop_process(process):
    if process and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


class WriteWatchdog:
    def __init__(self):
        self._lock = threading.Lock()
        self._started = None

    def begin(self, now):
        with self._lock:
            self._started = now

    def end(self):
        with self._lock:
            self._started = None

    def stalled(self, now, limit=8):
        with self._lock:
            return self._started is not None and now - self._started > limit


class PersistentPlayer:
    def __init__(self, command, log_path):
        self.command = command
        self.log_path = log_path
        self.process = None
        self.log = None
        self.guard = WriteWatchdog()
        self.finished = threading.Event()
        self.watchdog_thread = None
        self.killed_for_stall = False

    def start(self):
        if self.process is not None:
            self.check()
            return
        self.log = self.log_path.open('a', encoding='utf-8')
        try:
            self.process = subprocess.Popen(self.command, stdin=subprocess.PIPE,
                stdout=self.log, stderr=subprocess.STDOUT, bufsize=0)
        except Exception:
            self.log.close(); self.log = None
            raise
        self.finished.clear()
        self.killed_for_stall = False
        self.watchdog_thread = threading.Thread(target=self._watch, daemon=True)
        self.watchdog_thread.start()

    def check(self):
        if self.killed_for_stall:
            raise BrokenPipeError('mpv bloqueado al escribir vídeo; se reiniciará')
        if self.process is not None and self.process.poll() is not None:
            raise PlayerClosed(f'mpv terminó (código {self.process.returncode}). Registro: {self.log_path}')

    def _watch(self):
        while not self.finished.wait(0.5):
            if self.guard.stalled(time.monotonic()):
                self.killed_for_stall = True
                stop_process(self.process)
                return

    def write(self, payload):
        self.start()
        self.guard.begin(time.monotonic())
        try:
            view = memoryview(payload)
            while view:
                written = self.process.stdin.write(view)
                if not written:
                    raise BrokenPipeError('mpv pipe closed')
                view = view[written:]
        finally:
            self.guard.end()

    def close(self):
        self.finished.set()
        if self.watchdog_thread is not None:
            self.watchdog_thread.join(timeout=4)
        stop_process(self.process)
        if self.process is not None and self.process.stdin:
            self.process.stdin.close()
        self.process = None
        if self.log is not None:
            self.log.close(); self.log = None
        self.killed_for_stall = False
