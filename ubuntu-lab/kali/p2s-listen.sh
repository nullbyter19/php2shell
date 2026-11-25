#!/usr/bin/env bash
#
# PHP2Shell — reverse-shell listener (Kali pane 1). Written by r19.
#
#   ./p2s-listen.sh              # port 4444
#   ./p2s-listen.sh --lport 9001
#
# Keep this terminal open BEFORE firing the exploit. The shell lands here.

set -euo pipefail

LPORT="4444"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lport) LPORT="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if command -v rlwrap >/dev/null 2>&1; then
    echo "[*] listening on 0.0.0.0:${LPORT} (rlwrap: arrows and history work)"
    exec rlwrap -cAr ncat -lvnp "$LPORT"
fi

if command -v ncat >/dev/null 2>&1; then
    echo "[*] listening on 0.0.0.0:${LPORT} (ncat; no rlwrap)"
    exec ncat -lvnp "$LPORT"
fi

echo "[*] listening on 0.0.0.0:${LPORT} (netcat)"
exec nc -lvnp "$LPORT"
