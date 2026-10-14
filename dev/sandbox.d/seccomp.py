#!/usr/bin/env python3
"""The sandbox's seccomp profile: podman's default, without new user namespaces.

usage: seccomp.py BASE OUT

Podman's default profile lets a process in the container make a user
namespace of its own (`unshare -Ur`), which opens the kernel code that only a
namespaced root reaches. This copies BASE, takes clone, clone3 and unshare out
of every rule that allows them, and adds:

  * clone and unshare, allowed only when CLONE_NEWUSER is not in the flags;
  * clone3, refused with ENOSYS (its flags sit in a struct that seccomp cannot
    read); libc then falls back to clone.

x86_64 only: the flags are the first argument of both calls there.
"""
import json
import platform
import sys

CLONE_NEWUSER = 0x10000000
ENOSYS = 38
DENIED = ("clone", "clone3", "unshare")


def without_new_user_namespaces(profile):
    if platform.machine() != "x86_64":
        raise SystemExit("seccomp.py: the user-namespace rule is written for x86_64")
    rules = []
    for rule in profile["syscalls"]:
        names = [n for n in rule["names"] if n not in DENIED]
        if names:
            rules.append({**rule, "names": names})
    rules.append(
        {
            "names": ["clone", "unshare"],
            "action": "SCMP_ACT_ALLOW",
            "args": [{"index": 0, "value": CLONE_NEWUSER, "valueTwo": 0, "op": "SCMP_CMP_MASKED_EQ"}],
        }
    )
    rules.append({"names": ["clone3"], "action": "SCMP_ACT_ERRNO", "errnoRet": ENOSYS})
    return {**profile, "syscalls": rules}


def main(argv):
    if len(argv) != 3:
        raise SystemExit(__doc__)
    with open(argv[1]) as f:
        base = json.load(f)
    with open(argv[2], "w") as f:
        json.dump(without_new_user_namespaces(base), f)


if __name__ == "__main__":
    main(sys.argv)
