import pathlib
import socket
import sys
import threading
import unittest
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'windows'))
from protocol import HEADER, MAX_PAYLOAD, read_exact, read_frame
from mirror import player_args

class Fragmented:
    def __init__(self, data, step=1): self.data, self.step = data, step
    def recv(self, size):
        part, self.data = self.data[:min(size, self.step)], self.data[min(size, self.step):]
        return part

class ProtocolTests(unittest.TestCase):
    def packet(self, payload=b'\x00\x00\x00\x01\x65abc', seq=42):
        return HEADER.pack(b'NM01', len(payload), seq, 1000000, 2345) + payload
    def test_fragmentation(self):
        self.assertEqual(read_frame(Fragmented(self.packet())), (42, 1000000, 2345, b'\0\0\0\1\x65abc'))
    def test_consecutive_frames(self):
        sock = Fragmented(self.packet(seq=1) + self.packet(seq=5), 7)
        self.assertEqual(read_frame(sock)[0], 1)
        self.assertEqual(read_frame(sock)[0], 5)
    def test_eof_header(self):
        with self.assertRaises(EOFError): read_frame(Fragmented(self.packet()[:20]))
    def test_eof_payload(self):
        with self.assertRaises(EOFError): read_frame(Fragmented(self.packet()[:-1]))
    def test_reject_bad_magic(self):
        with self.assertRaises(ValueError): read_frame(Fragmented(b'BAD!' + self.packet()[4:]))
    def test_reject_unbounded_lengths(self):
        for size in (0, MAX_PAYLOAD + 1, 0xffffffff):
            with self.subTest(size=size), self.assertRaises(ValueError):
                read_frame(Fragmented(HEADER.pack(b'NM01', size, 0, 0, 0)))
    def test_real_tcp_ack(self):
        listener = socket.socket()
        listener.bind(('127.0.0.1', 0)); listener.listen(1)
        errors = []
        def producer():
            try:
                with listener.accept()[0] as connection:
                    connection.settimeout(2)
                    for seq in range(30):
                        connection.sendall(self.packet(seq=seq))
                        self.assertEqual(read_exact(connection, 1), b'A')
            except Exception as error: errors.append(error)
        thread = threading.Thread(target=producer); thread.start()
        with socket.create_connection(listener.getsockname(), timeout=2) as connection:
            for seq in range(30):
                self.assertEqual(read_frame(connection)[0], seq)
                connection.sendall(b'A')
        thread.join(3); listener.close()
        self.assertFalse(thread.is_alive()); self.assertEqual(errors, [])
    def test_mpv_fps_option_regression(self):
        for gaming in (True, False):
            self.assertFalse(any(arg.startswith('--fps=') for arg in player_args('mpv.exe', gaming)))
        self.assertNotIn('--container-fps-override=60', player_args('mpv.exe', True))
        quality = player_args('mpv.exe', False)
        self.assertIn('--correct-pts=no', quality)
        self.assertIn('--container-fps-override=60', quality)

    def test_gaming_arguments(self):
        command = player_args('mpv.exe', True)
        self.assertIn('--hwdec=d3d11va', command)
        self.assertIn('--untimed', command)
        self.assertNotIn('--untimed', player_args('mpv.exe', False))

if __name__ == '__main__': unittest.main()
