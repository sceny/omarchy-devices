#!/usr/bin/env python3
"""A working tree's tracked files as a tar on stdout, for `dev/sandbox dev sync`.

usage: git -C TREE ls-files -z | tree_tar.py TREE MAX_BYTES

Only the paths git tracks (a new file is `git add`ed first), with the bytes
they have in the working tree now. Regular files only: a symbolic link, a
socket, a fifo and a submodule are left out, and so is a path that leaves the
tree or has a part git itself would act on (.git). Nothing untracked or ignored
is read, so a scratch file or an environment file next to the code stays on
this machine. Fails (exit 1) when the tree is larger than MAX_BYTES.
"""
import os
import stat
import sys
import tarfile


def main(argv):
    tree = os.path.realpath(argv[0])
    limit = int(argv[1])
    names = [n for n in sys.stdin.buffer.read().split(b"\0") if n]
    total = left = 0
    with tarfile.open(fileobj=sys.stdout.buffer, mode="w|", format=tarfile.PAX_FORMAT) as tf:
        for raw in names:
            name = os.fsdecode(raw)
            parts = name.split("/")
            if name.startswith("/") or any(p in ("", ".", "..", ".git") for p in parts):
                left += 1
                continue
            path = os.path.join(tree, name)
            try:
                st = os.lstat(path)
            except OSError:
                left += 1  # tracked but deleted in the working tree
                continue
            real = os.path.realpath(os.path.dirname(path))
            if not stat.S_ISREG(st.st_mode) or not (real == tree or real.startswith(tree + os.sep)):
                left += 1
                continue
            total += st.st_size
            if total > limit:
                print(f"the tree is larger than {limit} bytes", file=sys.stderr)
                return 1
            info = tf.gettarinfo(path, arcname=name)
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mode = 0o755 if st.st_mode & 0o111 else 0o644
            with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as f:
                tf.addfile(info, f)
    print(f"{len(names) - left} files, {total} bytes, {left} left out", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
