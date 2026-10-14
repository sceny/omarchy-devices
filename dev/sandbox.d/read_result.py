#!/usr/bin/env python3
"""A unit's result tar, read as data and written under a directory the host made.

usage: read_result.py ARCHIVE DEST ROOT LABEL LIMIT MAX_MEMBERS [--png-dir DIR | --only-png [--expect DIR]]

Nothing in the archive is trusted: not a name, a kind, a size or a count.

  * Regular files and directories only (no link, device, fifo), at most 12
    deep, no existing file overwritten (O_EXCL, O_NOFOLLOW).
  * Every name part starts with a letter or a digit and has plain characters
    only, so nothing lands as .git, .envrc, .claude or any other dot-name. The
    names that tools load as instructions or settings (CLAUDE.md, AGENTS.md,
    GEMINI.md, mise.toml, conftest.py ...) are refused in any case, as are
    HEAD, objects and refs, which make a directory a bare git repository. A
    result tree is never a repository, an environment file or a set of
    instructions to whoever opens a shell, an editor or an agent in it.
  * A PNG is not written to DEST but to --png-dir, to be re-encoded in a
    container of its own; any other image format is refused. With --only-png
    the archive is that container's output: PNGs only, and --expect names the
    directory sent in, so a PNG that did not come back is listed.
  * Sizes (per file, and ROOT's total) and the number of members (directories
    included, ROOT's total) are limited.

Every refusal is a line in ROOT/SKIPPED.txt, "LABEL: <name as repr()>: <why>":
the contributor's text is escaped, never copied as it is. Exit 0 when the
archive was read to its end, 3 when it could not be, 4 when it was cut at the
member limit.
"""
import argparse
import os
import re
import sys
import struct
import tarfile
import zlib

PART = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._@+=,-]{0,119}$")
LOADED_BY_TOOLS = {
    "claude.md", "claude.local.md", "agents.md", "agents.override.md", "gemini.md", "mise", "copilot-instructions.md",
    "mise.toml", "mise.local.toml", "conftest.py", "sitecustomize.py", "usercustomize.py",
    "pytest.ini", "tox.ini", "setup.cfg", "pyproject.toml", "package.json", "makefile",
    "justfile", "head", "objects", "refs",
}
OTHER_IMAGES = (".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".tif", ".tiff", ".ico", ".avif", ".heic", ".apng", ".xpm", ".ppm")
PER_FILE = 200 * 1024 * 1024
MAX_DEPTH = 12
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_KEPT = (b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND")
PNG_MAX_BYTES = 64 * 1024 * 1024
PNG_MAX_EDGE = 16384
PNG_MAX_PIXELS = 40_000_000


def clean_png(data):
    """The picture of a PNG the re-encoder wrote, as a PNG of image chunks only; ValueError when it is not one.

    The signature, the order of chunks (IHDR first, IEND last and alone), every
    CRC and the size limits are checked; only IHDR, PLTE, tRNS, IDAT and IEND
    are kept, so no text, profile or unknown chunk reaches a viewer on the host.
    """
    if len(data) > PNG_MAX_BYTES or data[:8] != PNG_SIGNATURE:
        raise ValueError("not a PNG within the limits")
    out, pos, seen_idat, ended = [PNG_SIGNATURE], 8, False, False
    while pos < len(data):
        if ended or pos + 12 > len(data):
            raise ValueError("bytes outside the chunks")
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        end = pos + 12 + length
        if length > PNG_MAX_BYTES or end > len(data):
            raise ValueError("a chunk runs past the end")
        body = data[pos + 8:pos + 8 + length]
        if struct.unpack(">I", data[end - 4:end])[0] != zlib.crc32(kind + body):
            raise ValueError("a chunk fails its checksum")
        if pos == 8:
            if kind != b"IHDR" or length != 13:
                raise ValueError("IHDR is not first")
            w, h = struct.unpack(">II", body[:8])
            if not (0 < w <= PNG_MAX_EDGE and 0 < h <= PNG_MAX_EDGE and w * h <= PNG_MAX_PIXELS):
                raise ValueError("picture too large")
        elif kind == b"IHDR":
            raise ValueError("a second IHDR")
        seen_idat = seen_idat or kind == b"IDAT"
        ended = kind == b"IEND"
        if kind in PNG_KEPT:
            out.append(data[pos:end])
        pos = end
    if not (seen_idat and ended):
        raise ValueError("no image data or no IEND")
    return b"".join(out)


def refusal(parts):
    """Why a name is not taken, or None."""
    if len(parts) > MAX_DEPTH:
        return "name: too deep"
    for p in parts:
        if not PART.match(p):
            return "name"
        if p.lower() in LOADED_BY_TOOLS or re.match(r"^mise\.[a-z0-9._-]+\.toml$", p.lower()):
            return "name: a file that tools load as instructions or settings"
    return None


def count_existing(*bases):
    members = total = 0
    for base in bases:
        if base and os.path.isdir(base):
            for r, dirs, files in os.walk(base):
                members += len(dirs) + len(files)
                for f in files:
                    total += os.lstat(os.path.join(r, f)).st_size
    return members, total


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("archive")
    ap.add_argument("dest")
    ap.add_argument("root")
    ap.add_argument("label")
    ap.add_argument("limit", type=int)
    ap.add_argument("max_members", type=int)
    ap.add_argument("--png-dir")
    ap.add_argument("--only-png", action="store_true")
    ap.add_argument("--expect")
    a = ap.parse_args(argv)

    skipped, count = [], 0
    members, total = count_existing(a.root, a.png_dir)
    os.makedirs(a.dest, exist_ok=True)

    def skip(name, why):
        skipped.append(f"{a.label}: {name[:80]!r}: {why}")

    def finish(status):
        if a.expect and os.path.isdir(a.expect):
            for r, _dirs, files in os.walk(a.expect):
                for f in files:
                    rel = os.path.relpath(os.path.join(r, f), a.expect)
                    if not os.path.lexists(os.path.join(a.dest, rel)):
                        skip(rel, "a picture that could not be re-encoded safely")
        with open(os.path.join(a.root, "SKIPPED.txt"), "a") as f:
            f.write("\n".join(skipped) + ("\n" if skipped else ""))
        print(f"{count} files, {total} bytes, {len(skipped)} skipped")
        return status

    try:
        tf = tarfile.open(a.archive, "r:")
    except (tarfile.TarError, OSError) as e:
        skipped.append(f"{a.label}: the archive is unreadable: {e!r}"[:200])
        return finish(3)
    status = 0
    with tf:
        try:
            for m in tf:
                members += 1
                if members > a.max_members:
                    skipped.append(f"{a.label}: more than {a.max_members} members: the rest was not read")
                    status = 4
                    break
                name = m.name[2:] if m.name.startswith("./") else m.name
                if name in ("", "."):
                    continue
                parts = name.split("/")
                if parts[-1] == "" and len(parts) > 1:
                    parts = parts[:-1]
                why = refusal(parts)
                if why:
                    skip(m.name, why)
                    continue
                low = parts[-1].lower()
                if m.isreg() and low.endswith(OTHER_IMAGES):
                    skip(m.name, "an image that is not a PNG")
                    continue
                if a.only_png and m.isreg() and not low.endswith(".png"):
                    skip(m.name, "not a PNG")
                    continue
                base = a.dest
                if m.isreg() and low.endswith(".png") and not a.only_png:
                    if not a.png_dir:
                        skip(m.name, "a PNG with nowhere to be re-encoded")
                        continue
                    base = a.png_dir
                target = os.path.join(base, *parts)
                if m.isdir():
                    os.makedirs(target, mode=0o755, exist_ok=True)
                    continue
                if not m.isreg():
                    skip(m.name, "not a regular file")
                    continue
                if m.size > PER_FILE or total + m.size > a.limit:
                    skip(m.name, f"too large ({m.size} bytes)")
                    continue
                src = tf.extractfile(m)
                picture = None
                if a.only_png:
                    try:
                        picture = clean_png(src.read(PNG_MAX_BYTES + 1))
                    except ValueError as e:
                        skip(m.name, f"the re-encoded picture fails the check: {e}")
                        continue
                os.makedirs(os.path.dirname(target), mode=0o755, exist_ok=True)
                try:
                    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
                except OSError as e:
                    skip(m.name, e.strerror or "cannot be written")
                    continue
                with os.fdopen(fd, "wb") as out:
                    if picture is not None:
                        out.write(picture)
                    else:
                        while True:
                            chunk = src.read(1 << 20)
                            if not chunk:
                                break
                            out.write(chunk)
                total += len(picture) if picture is not None else m.size
                count += 1
        except (tarfile.TarError, OSError, EOFError) as e:
            skipped.append(f"{a.label}: the archive stops early: {e!r}"[:200])
            status = 3
    return finish(status)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
