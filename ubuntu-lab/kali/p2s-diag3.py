#!/usr/bin/env python3
"""PHP2Shell - pre-demo check (Kali -> target, HTTP only).

Answers in 5 seconds the question that always shows up mid-demo: "is the target
in the state the shell step expects?". It exploits nothing: it only reads what
install.sh published.

    ./p2s-diag3.py --target http://192.0.2.20:8080

Checks, in order:
    1. GET /            -> is Apache serving the docroot?
    2. GET /ping.php    -> version, sapi, arch and pid (stable across requests?)
    3. GET /stage/s     -> is the payload in the docroot? is it instrumented?
    4. GET /p2s-stage.log -> has the stager ever run? with what result?
    5. TCP LHOST:LPORT  -> is the Kali listener up?

Exit: 0 = ready for the demo, 1 = something to fix before going on stage.
"""
from __future__ import annotations

import argparse
import re
import socket
import sys
import urllib.error
import urllib.request

TIMEOUT = 8.0


def fetch(base: str, path: str):
    """(status, body_bytes) without raising."""
    try:
        with urllib.request.urlopen(base + path, timeout=TIMEOUT) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, b""
    except (urllib.error.URLError, OSError) as exc:
        return 0, str(exc).encode()


def field(body: bytes, name: str) -> str:
    match = re.search(rb"^" + name.encode() + rb"=(.+)$", body, re.MULTILINE)
    return match.group(1).decode().strip() if match else ""


def tcp_probe(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=3):
            return True
    except OSError:
        return False


def main() -> int:
    ap = argparse.ArgumentParser(description="PHP2Shell lab diagnostic (HTTP only).")
    ap.add_argument("--target", required=True, help="e.g. http://192.0.2.20:8080")
    args = ap.parse_args()
    base = args.target.rstrip("/")
    problems = 0

    print(f"[*] target {base}")

    code, _ = fetch(base, "/")
    print(f"    1. GET /            {code}")
    if code != 200:
        print("       !! empty docroot or Apache stopped: on the target, ls -la ubuntu-lab/app")
        problems += 1

    _, ping = fetch(base, "/ping.php")
    version, sapi, arch, pid1 = (field(ping, k) for k in ("version", "sapi", "arch", "pid"))
    if ping:
        _, ping2 = fetch(base, "/ping.php")
        pid2 = field(ping2, "pid")
        same = "same worker" if pid1 and pid1 == pid2 else f"worker changed ({pid1}->{pid2})"
        print(f"    2. /ping.php        php={version} sapi={sapi} arch={arch} pid={pid1} ({same})")
        if pid1 and pid2 and pid1 != pid2:
            problems += 1
    else:
        print("    2. /ping.php        unavailable (P2S_DEBUG=0?) - no version/worker")
        problems += 1

    code, stager = fetch(base, "/stage/s")
    if code == 200 and stager:
        lhost = field(stager, "LHOST").strip('"')
        lport = field(stager, "LPORT").strip('"')
        instrumented = b"p2s-stage.log" in stager
        state = "yes" if instrumented else "NO (old install.sh)"
        print(f"    3. /stage/s         {len(stager)} bytes -> {lhost}:{lport} "
              f"instrumented={state}")
        if not instrumented:
            print("       !! no HTTP proof possible: run install.sh again on the target")
            problems += 1
    else:
        print(f"    3. /stage/s         {code} - payload missing (install.sh not run?)")
        lhost = lport = ""
        problems += 1

    code, log = fetch(base, "/p2s-stage.log")
    if code == 200 and log:
        lines = [ln for ln in log.decode(errors="replace").splitlines() if ln.strip()]
        last = lines[-3:]
        verdict = "connect-ok" if any("connect-ok" in ln for ln in last) else (
            "connect-fail" if any("connect-fail" in ln for ln in last) else "no connect yet")
        print(f"    4. /p2s-stage.log   {len(lines)} line(s), last state: {verdict}")
        for ln in last:
            print(f"       {ln}")
    else:
        print(f"    4. /p2s-stage.log   {code} - the stager never ran (or is not instrumented)")

    if lhost and lport.isdigit():
        up = tcp_probe(lhost, int(lport))
        print(f"    5. TCP {lhost}:{lport}   {'accepts connection' if up else 'REFUSED/not listening'}")
        if not up:
            print("       !! start the listener: ./kali/p2s-listen.sh --lport " + lport)
            problems += 1
    else:
        print("    5. TCP listener     not verifiable (stager without LHOST/LPORT)")

    print()
    if problems:
        print(f"[!] {problems} item(s) to fix before the demo")
        return 1
    print("[+] ready: ./kali/p2s-run.sh --step shell")
    return 0


if __name__ == "__main__":
    sys.exit(main())
