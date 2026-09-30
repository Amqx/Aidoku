#!/usr/bin/env -S uv run --no-project
# /// script
# requires-python = ">=3.11"
# dependencies = ["lzfse==0.4.2"]
# ///
"""Convert an Aidoku backup from Amqx/Aidoku to the upstream binary-plist .aib format.

Usage: uv run convert_backup.py backup.aib [output.aib]
"""

import argparse
import datetime as dt
import plistlib
import struct
import sys
from pathlib import Path

import lzfse

MAGIC = b"AIB2"
HEADER_SIZE = 17
MAX_UNCOMPRESSED = 1_073_741_824  # Same limit as Aidoku.
APPLE_EPOCH = dt.datetime(2001, 1, 1, tzinfo=dt.UTC)


class FormatError(ValueError):
    """The input is not in the AIB2 format."""


def decompress_lzfse(data: bytes, size: int) -> bytes:
    try:
        output = lzfse.decompress(data)
    except lzfse.error as error:
        raise FormatError("LZFSE decoding failed") from error
    if len(output) != size:
        raise FormatError(f"LZFSE decoded {len(output)} bytes; expected {size}")
    return output


class CBORReader:
    def __init__(self, data: bytes):
        self.data = memoryview(data)
        self.position = 0
        self.strings: list[str] = []

    def take(self, size: int) -> memoryview:
        end = self.position + size
        if size < 0 or end > len(self.data):
            raise FormatError("Truncated CBOR payload")
        result = self.data[self.position:end]
        self.position = end
        return result

    def head(self) -> tuple[int, int, int]:
        initial = self.take(1)[0]
        major, additional = initial >> 5, initial & 31
        if additional < 24:
            argument = additional
        elif additional in (24, 25, 26, 27):
            argument = int.from_bytes(self.take(1 << (additional - 24)), "big")
        else:
            raise FormatError("Unsupported indefinite-length CBOR value")
        return major, additional, argument

    def read(self, depth: int = 0):
        if depth > 64:
            raise FormatError("CBOR nesting exceeds Aidoku's limit")
        major, additional, argument = self.head()
        if major == 0:
            return argument
        if major == 1:
            if argument > (1 << 63) - 1:
                raise FormatError("CBOR negative integer is out of range")
            return -1 - argument
        if major == 2:
            return bytes(self.take(argument))
        if major == 3:
            try:
                return self.take(argument).tobytes().decode("utf-8")
            except UnicodeDecodeError as error:
                raise FormatError("Invalid UTF-8 in CBOR") from error
        if major == 4:
            if argument > len(self.data) - self.position:
                raise FormatError("Invalid CBOR array length")
            return [self.read(depth + 1) for _ in range(argument)]
        if major == 5:
            if argument > (len(self.data) - self.position) // 2:
                raise FormatError("Invalid CBOR map length")
            result = {}
            for _ in range(argument):
                key = self.read(depth + 1)
                if not isinstance(key, str) or key in result:
                    raise FormatError("Invalid or duplicate CBOR map key")
                result[key] = self.read(depth + 1)
            return result
        if major == 6:
            value = self.read(depth + 1)
            if argument == 25:
                if not isinstance(value, int) or not 0 <= value < len(self.strings):
                    raise FormatError("Invalid CBOR string reference")
                return self.strings[value]
            if argument == 1001:
                if not isinstance(value, float):
                    raise FormatError("Invalid CBOR date")
                # plistlib represents binary-plist dates as naive UTC datetimes.
                return (APPLE_EPOCH + dt.timedelta(seconds=value)).replace(tzinfo=None)
            raise FormatError(f"Unsupported CBOR tag {argument}")
        if major == 7:
            if additional == 20:
                return False
            if additional == 21:
                return True
            if additional == 27:
                return struct.unpack(">d", argument.to_bytes(8, "big"))[0]
        raise FormatError(f"Unsupported CBOR value {major}:{additional}")

    def backup(self) -> dict:
        major, _, tag = self.head()
        if (major, tag) != (6, 256):
            raise FormatError("Missing CompactCBOR string namespace")
        major, _, count = self.head()
        if (major, count) != (4, 2):
            raise FormatError("Invalid CompactCBOR root")
        major, _, string_count = self.head()
        if major != 4 or string_count > len(self.data) - self.position:
            raise FormatError("Invalid CompactCBOR string table")
        for _ in range(string_count):
            major, _, length = self.head()
            if major != 3:
                raise FormatError("Non-string entry in CBOR string table")
            try:
                self.strings.append(self.take(length).tobytes().decode("utf-8"))
            except UnicodeDecodeError as error:
                raise FormatError("Invalid UTF-8 in string table") from error
        result = self.read()
        if self.position != len(self.data) or not isinstance(result, dict):
            raise FormatError("CBOR payload has extra data or no backup dictionary")
        return result


def convert(source: Path, destination: Path) -> None:
    if source.resolve() == destination.resolve():
        raise FormatError("Output must differ from input")
    if destination.exists():
        raise FileExistsError(f"Output already exists: {destination}")

    archive = source.read_bytes()
    if len(archive) < HEADER_SIZE or archive[:4] != MAGIC or archive[4] != 1:
        raise FormatError("Expected an AIB2 version 1 backup")
    size = int.from_bytes(archive[5:13], "big")
    summary_size = int.from_bytes(archive[13:17], "big")
    if not 0 < size <= MAX_UNCOMPRESSED or HEADER_SIZE + summary_size >= len(archive):
        raise FormatError("Invalid AIB2 header")
    summary = plistlib.loads(archive[HEADER_SIZE:HEADER_SIZE + summary_size])
    payload = decompress_lzfse(archive[HEADER_SIZE + summary_size:], size)
    backup = CBORReader(payload).backup()

    if backup.get("date") != summary.get("date"):
        raise FormatError("Backup date differs from AIB2 summary")
    for key, count in summary.get("counts", {}).items():
        value = backup.get(key)
        if not isinstance(value, (list, dict)) or len(value) != count:
            raise FormatError(f"Backup {key} count differs from AIB2 summary")

    old_format = plistlib.dumps(backup, fmt=plistlib.FMT_BINARY, sort_keys=False)
    if plistlib.loads(old_format) != backup:
        raise FormatError("Binary plist round-trip failed")
    with destination.open("xb") as output:
        output.write(old_format)
    print(f"Wrote {destination} ({len(old_format):,} bytes, binary plist)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="AIB2 .aib backup")
    parser.add_argument("destination", nargs="?", type=Path,
                        help="Old-format .aib output (default: SOURCE-old.aib)")
    args = parser.parse_args()
    destination = args.destination or args.source.with_name(args.source.stem + "-old.aib")
    try:
        convert(args.source, destination)
    except (OSError, ValueError, OverflowError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
