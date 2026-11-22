"""Fetch one official Godot export template from the multi-gigabyte TPZ."""

from __future__ import annotations

import argparse
import binascii
import os
import re
import struct
import tempfile
import urllib.request
import zlib

CHUNK = 8 * 1024 * 1024


def request_range(url: str, start: int | None, end: int | None, suffix: int | None = None):
    if suffix is not None:
        header = f"bytes=-{suffix}"
    else:
        header = f"bytes={start}-{end}"
    request = urllib.request.Request(url, headers={"Range": header, "User-Agent": "LumenDrift-build/1.0"})
    response = urllib.request.urlopen(request, timeout=180)
    if response.status != 206:
        response.close()
        raise RuntimeError(f"Godot download host did not honor byte ranges (HTTP {response.status}).")
    match = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", response.headers.get("Content-Range", ""))
    if not match:
        response.close()
        raise RuntimeError("Godot download host returned an invalid Content-Range header.")
    actual_start, actual_end, total = map(int, match.groups())
    data = response.read()
    final_url = response.geturl()
    response.close()
    if len(data) != actual_end - actual_start + 1:
        raise RuntimeError("Godot download host returned an incomplete byte range.")
    return data, final_url, actual_start, total


def find_entry(directory: bytes, wanted: bytes):
    cursor = 0
    while cursor + 46 <= len(directory):
        fields = struct.unpack_from("<4s6H3I5H2I", directory, cursor)
        if fields[0] != b"PK\x01\x02":
            break
        compressed_size, uncompressed_size = fields[8], fields[9]
        name_length, extra_length, comment_length = fields[10], fields[11], fields[12]
        local_offset = fields[16]
        name_start = cursor + 46
        name = directory[name_start : name_start + name_length]
        if name == wanted:
            if max(compressed_size, uncompressed_size, local_offset) == 0xFFFFFFFF:
                raise RuntimeError("ZIP64 entry layout is not supported by this small template extractor.")
            return fields[4], fields[7], compressed_size, uncompressed_size, local_offset, name_length, extra_length
        cursor = name_start + name_length + extra_length + comment_length
    raise RuntimeError(f"Official template archive has no {wanted.decode()} entry.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    url = (
        "https://downloads.godotengine.org/?flavor=stable&platform=templates"
        f"&slug=export_templates.tpz&version={args.version}"
    )

    tail, direct_url, tail_start, total_size = request_range(url, None, None, suffix=65536)
    end_record = tail.rfind(b"PK\x05\x06")
    if end_record < 0 or end_record + 22 > len(tail):
        raise RuntimeError("Could not find the export template archive directory.")
    record = struct.unpack_from("<4s4H2IH", tail, end_record)
    entry_count, directory_size, directory_offset = record[4], record[5], record[6]
    if entry_count == 0xFFFF or directory_size == 0xFFFFFFFF or directory_offset == 0xFFFFFFFF:
        raise RuntimeError("ZIP64 central directories are not supported by this template extractor.")

    if directory_offset >= tail_start and directory_offset + directory_size <= tail_start + len(tail):
        central = tail[directory_offset - tail_start : directory_offset - tail_start + directory_size]
    else:
        central, direct_url, _, _ = request_range(direct_url, directory_offset, directory_offset + directory_size - 1)

    wanted = b"templates/windows_release_x86_64.exe"
    compression, expected_crc, compressed_size, uncompressed_size, local_offset, _, _ = find_entry(central, wanted)
    local, direct_url, _, _ = request_range(direct_url, local_offset, local_offset + 29)
    local_header = struct.unpack("<4s5H3I2H", local)
    if local_header[0] != b"PK\x03\x04" or local_header[3] != compression:
        raise RuntimeError("The Windows template local ZIP header did not match its directory entry.")
    data_offset = local_offset + 30 + local_header[9] + local_header[10]

    destination = os.path.abspath(args.output)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="godot-template-", dir=os.path.dirname(destination))
    crc = 0
    written = 0
    decompressor = zlib.decompressobj(-15) if compression == 8 else None
    if compression not in (0, 8):
        os.close(fd)
        os.unlink(temporary)
        raise RuntimeError(f"Unsupported ZIP compression method: {compression}.")
    try:
        with os.fdopen(fd, "wb") as output:
            position = 0
            while position < compressed_size:
                count = min(CHUNK, compressed_size - position)
                chunk, direct_url, _, _ = request_range(
                    direct_url, data_offset + position, data_offset + position + count - 1
                )
                payload = decompressor.decompress(chunk) if decompressor else chunk
                output.write(payload)
                written += len(payload)
                crc = binascii.crc32(payload, crc)
                position += count
            if decompressor:
                payload = decompressor.flush()
                output.write(payload)
                written += len(payload)
                crc = binascii.crc32(payload, crc)
        if written != uncompressed_size or (crc & 0xFFFFFFFF) != expected_crc:
            raise RuntimeError("The downloaded Windows template failed its ZIP size or CRC check.")
        os.replace(temporary, destination)
    except Exception:
        if os.path.exists(temporary):
            os.unlink(temporary)
        raise
    print(f"Verified Windows x64 release template ({written:,} bytes) from the official Godot {args.version} archive.")


if __name__ == "__main__":
    main()

