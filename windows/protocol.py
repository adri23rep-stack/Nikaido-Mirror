"""NM01 framing. Times are sender-clock values; never subtract host time."""
import struct
HEADER = struct.Struct('!4sIQQQ')
MAX_PAYLOAD = 8 * 1024 * 1024

def read_exact(sock, size):
    chunks = bytearray()
    while len(chunks) < size:
        data = sock.recv(size - len(chunks))
        if not data:
            raise EOFError('USB stream closed')
        chunks.extend(data)
    return bytes(chunks)

def read_frame(sock):
    magic, length, sequence, capture_us, encode_us = HEADER.unpack(read_exact(sock, HEADER.size))
    if magic != b'NM01' or not 0 < length <= MAX_PAYLOAD:
        raise ValueError('Invalid NM01 frame header')
    return sequence, capture_us, encode_us, read_exact(sock, length)
