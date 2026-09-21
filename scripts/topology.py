#!/usr/bin/env python3
"""Eight-node P/D rendezvous over deployment-local shared storage."""

import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import stat
import sys
import time


SAFE = re.compile(r"[A-Za-z0-9_.-]{1,128}")
VALID_ROLES = {"P_ENTRY", "P_WORKER", "D_WORKER"}
MAX_AGE = 120


def private_ipv4(value):
    address = ipaddress.ip_address(value)
    if address.version != 4 or not address.is_private or address.is_loopback:
        raise ValueError("expected private non-loopback IPv4")
    return str(address)


def local_devices():
    devices = sorted(
        int(path.name.removeprefix("davinci"))
        for path in Path("/dev").glob("davinci*")
        if re.fullmatch(r"davinci[0-9]+", path.name)
        and stat.S_ISCHR(path.stat().st_mode)
    )
    if devices != list(range(8)):
        raise ValueError(f"expected devices 0..7, found {devices}")
    return devices


def select(records, cohort, own_host, own_ip, own_role, now):
    current = []
    for record in records:
        age = now - float(record["timestamp"])
        if record.get("cohort") != cohort or not -5 <= age <= MAX_AGE:
            continue
        current.append(
            {
                "hostname": str(record["hostname"]),
                "ip": private_ipv4(record["ip"]),
                "role": str(record["role"]),
                "devices": record["devices"],
            }
        )
    if len(current) != 8:
        raise ValueError("waiting for eight current registrations")
    if len({item["hostname"] for item in current}) != 8:
        raise ValueError("duplicate hostname")
    if len({item["ip"] for item in current}) != 8:
        raise ValueError("duplicate pod IP")
    if any(item["devices"] != list(range(8)) for item in current):
        raise ValueError("unexpected local NPU set")
    roles = [item["role"] for item in current]
    if roles.count("P_ENTRY") != 1 or roles.count("P_WORKER") != 3 or roles.count("D_WORKER") != 4:
        raise ValueError("expected 1 P_ENTRY, 3 P_WORKER, and 4 D_WORKER")
    prefill = sorted(
        [item for item in current if item["role"].startswith("P_")],
        key=lambda item: (0 if item["role"] == "P_ENTRY" else 1, item["hostname"]),
    )
    decode = sorted(
        [item for item in current if item["role"] == "D_WORKER"],
        key=lambda item: item["hostname"],
    )
    own = next(
        (
            item
            for item in current
            if item["hostname"] == own_host
            and item["ip"] == own_ip
            and item["role"] == own_role
        ),
        None,
    )
    if own is None:
        raise ValueError("local identity is absent from the selected cohort")
    side = "P" if own_role.startswith("P_") else "D"
    group = prefill if side == "P" else decode
    return {
        "side": side,
        "role": own_role,
        "position": next(i for i, item in enumerate(group) if item == own),
        "p_ips": [item["ip"] for item in prefill],
        "d_ips": [item["ip"] for item in decode],
        "p_master": prefill[0]["ip"],
        "d_master": decode[0]["ip"],
    }


def load(directory):
    records = []
    for path in sorted(directory.glob("*.json")):
        if path.is_symlink() or path.stat().st_size > 4096:
            raise ValueError("unsafe registration file")
        record = json.loads(path.read_text(encoding="utf-8"))
        if path.name != record["hostname"] + ".json":
            raise ValueError("registration filename mismatch")
        records.append(record)
    return records


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    cohort = os.environ.get("MODELARTS_COHORT_ID", "")
    role = os.environ.get("GLM52_ROLE", "")
    hostname = socket.gethostname()
    if not SAFE.fullmatch(cohort) or not SAFE.fullmatch(hostname):
        raise SystemExit("unsafe or missing cohort/hostname")
    if role not in VALID_ROLES:
        raise SystemExit("GLM52_ROLE must be P_ENTRY, P_WORKER, or D_WORKER")
    pod_ip = private_ipv4(os.environ.get("POD_IP", ""))
    record = {
        "hostname": hostname,
        "cohort": cohort,
        "role": role,
        "ip": pod_ip,
        "devices": local_devices(),
    }
    root = Path(os.environ.get("RENDEZVOUS_ROOT", "/logs/rendezvous"))
    directory = root / cohort
    if root.is_symlink() or directory.is_symlink():
        raise SystemExit("symlink rendezvous paths are forbidden")
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / f"{hostname}.json"
    temporary = directory / f"{hostname}.{os.getpid()}.tmp"
    deadline = time.monotonic() + args.timeout
    last_log = 0.0
    while time.monotonic() < deadline:
        record["timestamp"] = time.time()
        temporary.write_text(json.dumps(record), encoding="utf-8")
        temporary.replace(destination)
        try:
            result = select(load(directory), cohort, hostname, pod_ip, role, time.time())
            args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
            return
        except (OSError, KeyError, TypeError, ValueError) as exc:
            if time.monotonic() - last_log > 30:
                print(f"topology waiting: {type(exc).__name__}: {exc}", file=sys.stderr)
                last_log = time.monotonic()
        time.sleep(1)
    raise TimeoutError("topology rendezvous timed out")


if __name__ == "__main__":
    main()
