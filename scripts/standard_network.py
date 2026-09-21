#!/usr/bin/env python3
"""Resolve POD_IP to one private local IPv4 interface."""

import fcntl
import ipaddress
import os
import re
import socket
import struct


def interfaces():
    result = []
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        for _, name in socket.if_nameindex():
            if len(name.encode()) >= 16:
                continue
            try:
                info = fcntl.ioctl(
                    probe.fileno(), 0x8915, struct.pack("256s", name.encode())
                )
            except OSError:
                continue
            result.append((name, socket.inet_ntoa(info[20:24])))
    return result


def main():
    requested = os.environ.get("POD_IP", "").strip()
    candidates = []
    for name, value in interfaces():
        address = ipaddress.ip_address(value)
        if (
            name != "lo"
            and re.fullmatch(r"[A-Za-z0-9_.:-]+", name)
            and address.version == 4
            and address.is_private
            and not address.is_loopback
            and not address.is_link_local
        ):
            candidates.append((name, value))
    if requested:
        candidates = [item for item in candidates if item[1] == requested]
    if len(candidates) != 1:
        raise SystemExit("POD_IP must resolve to exactly one private interface")
    print(candidates[0][1], candidates[0][0])


if __name__ == "__main__":
    main()
