#!/usr/bin/env python3
"""Re-encode the PNGs a unit made, in a container that holds nothing else.

usage: reencode.py <dir of PNGs> <dir for the copies>

Run by `dev/sandbox` in a second container: no contributor code, no network,
no device, a read-only root, and the quarantined PNGs mounted read-only. A PNG
is read by its header first (size and pixel limits, checked before any pixel
is decoded), decoded by GdkPixbuf (glycin's loaders, each in bubblewrap), and
written again as a plain PNG: pixels only, no text, profile or other chunk.
Each file is decoded by a process of its own with a time limit, so one that
hangs or runs out of memory costs only itself. A file that fails any step is dropped; the host lists it in SKIPPED.txt by
comparing names, so nothing here is trusted to say so.
"""
import os
import struct
import subprocess
import sys

import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf  # noqa: E402

MAX_BYTES = 64 * 1024 * 1024
MAX_EDGE = 16384
MAX_PIXELS = 40_000_000
SIGNATURE = b"\x89PNG\r\n\x1a\n"
TIME_LIMIT = 30


def header(path):
    """(width, height) from the PNG header, or None when it is not one."""
    with open(path, "rb") as f:
        head = f.read(33)
    if len(head) < 33 or head[:8] != SIGNATURE or head[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", head[16:24])


def decode(src, dst):
    """In the child: header limits, decode, write again. Exit status 0 only when dst is written."""
    if os.path.getsize(src) > MAX_BYTES:
        return "file too large"
    size = header(src)
    if size is None:
        return "not a PNG"
    w, h = size
    if not (0 < w <= MAX_EDGE and 0 < h <= MAX_EDGE and w * h <= MAX_PIXELS):
        return f"picture too large ({w}x{h})"
    pixbuf = GdkPixbuf.Pixbuf.new_from_file(src)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    pixbuf.savev(dst, "png", [], [])
    return None


def one(src, dst):
    """Re-encode in a child process; a reason, or None."""
    if os.path.islink(src) or not os.path.isfile(src):
        return "not a regular file"
    try:
        done = subprocess.run([sys.executable, __file__, "--one", src, dst], capture_output=True, timeout=TIME_LIMIT)
    except subprocess.TimeoutExpired:
        return "took too long"
    if done.returncode != 0:
        why = done.stdout.decode("ascii", "replace").strip()[:80]
        return why or f"could not be decoded (exit {done.returncode})"
    return None


def main(argv):
    if argv[0] == "--one":
        try:
            why = decode(argv[1], argv[2])
        except Exception as e:  # a hostile file may fail any way it likes
            why = type(e).__name__
        if why:
            print(why)
            return 1
        return 0
    src_root, dst_root = argv[:2]
    kept = dropped = 0
    for root, _dirs, files in os.walk(src_root):
        for name in sorted(files):
            src = os.path.join(root, name)
            rel = os.path.relpath(src, src_root)
            why = one(src, os.path.join(dst_root, rel))
            if why:
                dropped += 1
                print(f"dropped {rel!r}: {why}", file=sys.stderr)
            else:
                kept += 1
    print(f"re-encoded {kept}, dropped {dropped}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
