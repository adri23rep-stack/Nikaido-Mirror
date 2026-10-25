"""Bounded NM01/NM02 framing. All durations use only the sender's clock."""
import struct
HEADER = struct.Struct('!4sIQQQ')
DIAGNOSTICS = struct.Struct('!7Q')
DIAGNOSTIC_FIELDS = ('queue_us', 'prepare_us', 'callback_queue_us', 'previous_ack_us',
                     'source_work_us', 'app_state', 'thermal_state')
MAX_PAYLOAD = 8 * 1024 * 1024


def read_exact(sock, size):
    chunks = bytearray()
    while len(chunks) < size:
        data = sock.recv(size - len(chunks))
        if not data:
            raise EOFError('USB stream closed')
        chunks.extend(data)
    return bytes(chunks)


def read_frame_details(sock):
    magic, length, sequence, capture_us, encode_us = HEADER.unpack(read_exact(sock, HEADER.size))
    if magic not in (b'NM01', b'NM02') or not 0 < length <= MAX_PAYLOAD:
        raise ValueError('Invalid NM01/NM02 frame header')
    details = {}
    if magic == b'NM02':
        details = dict(zip(DIAGNOSTIC_FIELDS, DIAGNOSTICS.unpack(read_exact(sock, DIAGNOSTICS.size))))
    return sequence, capture_us, encode_us, read_exact(sock, length), details


def read_frame(sock):
    # Keep the original reader API available to protocol users.
    return read_frame_details(sock)[:4]
