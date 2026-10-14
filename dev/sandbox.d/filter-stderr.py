#!/usr/bin/env python3
"""The container's stderr as text for the operator's terminal.

usage: filter-stderr.py [PREFIX]

Reads stdin and writes stdout: only printable characters and newline or tab
(so no escape sequence, bell, carriage return or bidirectional override
reaches the terminal), each line cut at MAX_LINE characters, at most MAX_TOTAL
bytes written in all. Past that the rest is read and dropped, so the writer is
never blocked and nothing piles up in memory.
"""
import codecs
import os
import sys

MAX_LINE = 4096
MAX_TOTAL = 16 * 1024 * 1024
CUT = "…"
DROPPED = "[further output dropped]"


def main(prefix):
    decoder = codecs.getincrementaldecoder("utf-8")("replace")
    out = sys.stdout.buffer
    written = 0
    column = 0
    stopped = False
    fd = sys.stdin.fileno()
    while True:
        chunk = os.read(fd, 65536)
        if not chunk:
            break
        if stopped:
            continue
        pieces = []
        for ch in decoder.decode(chunk):
            if ch == "\n":
                pieces.append("\n")
                column = 0
                continue
            if ch != "\t" and not ch.isprintable():
                continue
            if column == 0:
                pieces.append(prefix)
            column += 1
            if column <= MAX_LINE:
                pieces.append(ch)
            elif column == MAX_LINE + 1:
                pieces.append(CUT)
        data = "".join(pieces).encode()
        if written + len(data) > MAX_TOTAL:
            data = data[: MAX_TOTAL - written].decode("utf-8", "ignore").encode()
            data += f"\n{prefix}{DROPPED}\n".encode()
            stopped = True
        written += len(data)
        out.write(data)
        out.flush()
    if column:
        out.write(b"\n")
        out.flush()


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "    ")
