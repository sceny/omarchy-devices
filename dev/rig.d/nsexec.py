#!/usr/bin/env python3
"""nsexec.py PID -- COMMAND...

Join the user, network and mount namespaces of PID and exec COMMAND there as
the same uid, keeping CAP_SYS_ADMIN across the exec. That one capability is
what lets sshfs mount the phone's storage inside the rig; nsenter cannot keep
it, because a plain exec drops it for a uid that is not root.
"""
import ctypes
import os
import struct
import sys

CLONE_NEWNS, CLONE_NEWUSER, CLONE_NEWNET = 0x00020000, 0x10000000, 0x40000000
CAP_SYS_ADMIN = 21
PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE = 47, 2
SYS_CAPGET, SYS_CAPSET = 125, 126
CAP_V3 = 0x20080522


def fail(message):
    sys.stderr.write("nsexec: %s\n" % message)
    sys.exit(126)


def main():
    if len(sys.argv) < 4 or sys.argv[2] != "--":
        fail("usage: nsexec.py PID -- COMMAND...")
    pid, command = sys.argv[1], sys.argv[3:]
    libc = ctypes.CDLL(None, use_errno=True)
    cwd = os.getcwd()

    for name, flag in (("user", CLONE_NEWUSER), ("net", CLONE_NEWNET), ("mnt", CLONE_NEWNS)):
        try:
            fd = os.open("/proc/%s/ns/%s" % (pid, name), os.O_RDONLY)
        except OSError as error:
            fail("cannot open the %s namespace of %s: %s" % (name, pid, error))
        if libc.setns(fd, flag) != 0:
            fail("setns %s: %s" % (name, os.strerror(ctypes.get_errno())))
        os.close(fd)

    header = struct.pack("Ii", CAP_V3, 0)
    data = ctypes.create_string_buffer(24)
    if libc.syscall(SYS_CAPGET, header, data) != 0:
        fail("capget: %s" % os.strerror(ctypes.get_errno()))
    eff, perm, inh, eff2, perm2, inh2 = struct.unpack("6I", data.raw)
    inh |= 1 << CAP_SYS_ADMIN
    data = struct.pack("6I", eff, perm, inh, eff2, perm2, inh2)
    if libc.syscall(SYS_CAPSET, header, data) != 0:
        fail("capset: %s" % os.strerror(ctypes.get_errno()))
    if libc.prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE, CAP_SYS_ADMIN, 0, 0) != 0:
        fail("ambient CAP_SYS_ADMIN: %s" % os.strerror(ctypes.get_errno()))

    try:
        os.chdir(cwd)
    except OSError:
        os.chdir("/")
    try:
        os.execvp(command[0], command)
    except OSError as error:
        fail("%s: %s" % (command[0], error))


main()
