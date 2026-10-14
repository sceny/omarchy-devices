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
import tarfile

PART = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._@+=,-]{0,119}$")
LOADED_BY_TOOLS = {
    "claude.md", "claude.local.md", "agents.md", "gemini.md", "copilot-instructions.md",
    "mise.toml", "mise.local.toml", "conftest.py", "sitecustomize.py", "usercustomize.py",
    "pytest.ini", "tox.ini", "setup.cfg", "pyproject.toml", "package.json", "makefile",
    "justfile", "head", "objects", "refs",
}
OTHER_IMAGES = (".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".tif", ".tiff", ".ico", ".avif", ".heic", ".apng", ".xpm", ".ppm")
PER_FILE = 200 * 1024 * 1024
MAX_DEPTH = 12


def refusal(parts):
    """Why a name is not taken, or None."""
    if len(parts) > MAX_DEPTH:
        return "name: too deep"
    for p in parts:
        if not PART.match(p):
            return "name"
        if p.lower() in LOADED_BY_TOOLS:
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
                os.makedirs(os.path.dirname(target), mode=0o755, exist_ok=True)
                src = tf.extractfile(m)
                try:
                    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
                except OSError as e:
                    skip(m.name, e.strerror or "cannot be written")
                    continue
                with os.fdopen(fd, "wb") as out:
                    while True:
                        chunk = src.read(1 << 20)
                        if not chunk:
                            break
                        out.write(chunk)
                total += m.size
                count += 1
        except (tarfile.TarError, OSError, EOFError) as e:
            skipped.append(f"{a.label}: the archive stops early: {e!r}"[:200])
            status = 3
    return finish(status)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
