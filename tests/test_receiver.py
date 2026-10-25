import pathlib
import socket
import sys
import tempfile
import unittest
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'windows'))
from protocol import HEADER, DIAGNOSTICS
from mirror import receive_frame
from player import WriteWatchdog, PersistentPlayer, PlayerClosed


class InterruptedSocket:
    def __init__(self, events):
        self.events = list(events)
    def recv(self, size):
        item = self.events.pop(0)
        if isinstance(item, Exception):
            raise item
        if len(item) > size:
            self.events.insert(0, item[size:])
        return item[:size]


class PlayerStub:
    def check(self):
        pass


class ReceiverTests(unittest.TestCase):
    def test_idle_does_not_discard_partial_frame(self):
        payload = b'\0\0\0\1\x65video'
        packet = HEADER.pack(b'NM02', len(payload), 7, 100, 200) + DIAGNOSTICS.pack(1, 2, 3, 4, 5, 2, 2) + payload
        events = []
        for offset in range(0, len(packet), 3):
            events.extend([packet[offset:offset+3], socket.timeout()])
        messages = []
        result = receive_frame(InterruptedSocket(events), PlayerStub(), clock=lambda: 0, notify=messages.append)
        self.assertEqual(result[:4], (7, 100, 200, payload))
        self.assertEqual(result[4]['thermal_state'], 2)
        self.assertEqual(len(messages), 1)
    def test_long_silence_requests_reconnect(self):
        clock = iter([0, 31])
        with self.assertRaises(TimeoutError):
            receive_frame(InterruptedSocket([socket.timeout()]), PlayerStub(), clock=lambda: next(clock), notify=lambda x: None)
    def test_user_closes_during_silence(self):
        class Closed:
            def check(self): raise PlayerClosed('closed')
        with self.assertRaises(PlayerClosed):
            receive_frame(InterruptedSocket([socket.timeout()]), Closed())
    def test_watchdog_only_times_active_write(self):
        guard = WriteWatchdog()
        self.assertFalse(guard.stalled(100000))
        guard.begin(100)
        self.assertFalse(guard.stalled(107))
        self.assertTrue(guard.stalled(109))
        guard.end()
        self.assertFalse(guard.stalled(100000))
    def test_reusing_player_keeps_process_and_pipe(self):
        with tempfile.TemporaryDirectory() as directory:
            player = PersistentPlayer([sys.executable, '-u', '-c', 'import sys; sys.stdin.buffer.read()'], pathlib.Path(directory) / 'log')
            try:
                player.write(b'first connection')
                process = player.process
                # A new USB connection calls start again; do not replace decoder/window.
                player.start()
                player.write(b'next connection')
                self.assertIs(player.process, process)
                self.assertIsNone(process.poll())
                self.assertFalse(player.guard.stalled(100000000))
            finally:
                player.close()
            self.assertIsNotNone(process.poll())


if __name__ == '__main__': unittest.main()
