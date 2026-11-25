#!/usr/bin/env bash
#
# PHP2Shell — take the lab down. Lab written by r19.
#
#   sudo ./uninstall.sh           # stop the container, keep Docker and files
#   sudo ./uninstall.sh --purge   # also delete stager, storage and docker/.env
#
# Run this before plugging the VM into any network that is not the event's:
# the stager in app/stage/s is a working reverse shell waiting for an IP.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PURGE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --purge) PURGE=1; shift ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "[!] run as root: sudo ./uninstall.sh" >&2; exit 1; }

if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi
if "${DOCKER[@]}" compose version >/dev/null 2>&1; then COMPOSE=("${DOCKER[@]}" compose)
else COMPOSE=(docker-compose); fi

( cd "$ROOT/docker" && "${COMPOSE[@]}" down -v ) || true
echo "[*] container removed"

rm -f "$ROOT/app/stage/s"
echo "[*] stager removed"

if [[ $PURGE -eq 1 ]]; then
    rm -rf "$ROOT/storage" "$ROOT/app/stage" "$ROOT/docker/.env"
    echo "[*] storage/, app/stage/ and docker/.env deleted"
fi

cat <<EOF

The target is no longer up. Check:

  docker ps --filter name=p2s-ubuntu-victim
  ss -ltnp | grep -E ':(8080|80) '

The php:8.5.11-apache image stays on disk (it is vulnerable, but only runs if
you bring the compose up again). To remove it:

  docker rmi php:8.5.11-apache
EOF
