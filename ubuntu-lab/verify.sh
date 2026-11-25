#!/usr/bin/env bash
#
# PHP2Shell — verify the installed target (run on Ubuntu, after install.sh).
# Lab written by r19.
#
#   ./verify.sh
#
# Checks, in order: container up, app answering, PHP 8.5.11, SAME process across
# two requests (1 worker), docroot and storage writable by www-data (uid 33), the
# php.ini values the chain depends on, and the stager carrying the Kali IP.
#
# Exits non-zero if any essential check fails. Runs as root or as a user in the
# docker group.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILS=0

pass() { printf '  \033[32mok\033[0m    %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAILS=$((FAILS + 1)); }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$1"; }

PORT="$(sed -n 's/^P2S_PORT=//p' "$ROOT/docker/.env" 2>/dev/null | head -n1)"
[[ -n "$PORT" ]] || PORT=8080

if docker info >/dev/null 2>&1; then DOCKER=(docker)
elif command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then DOCKER=(sudo docker)
else echo "[!] no access to Docker (use root or join the docker group)" >&2; exit 2; fi

if "${DOCKER[@]}" compose version >/dev/null 2>&1; then COMPOSE=("${DOCKER[@]}" compose)
elif command -v docker-compose >/dev/null 2>&1; then COMPOSE=(docker-compose)
else echo "[!] docker compose not found" >&2; exit 2; fi

in_container() { ( cd "$ROOT/docker" && "${COMPOSE[@]}" exec -T "$@" ); }

echo
echo "PHP2Shell — target verification (port ${PORT})"
echo

# --- 1. container ----------------------------------------------------------
RUNNING="$("${DOCKER[@]}" inspect -f '{{.State.Running}}' p2s-ubuntu-victim 2>/dev/null || echo missing)"
if [[ "$RUNNING" == "true" ]]; then pass "victim container is running"
else fail "victim container is not running (cd docker && sudo ${COMPOSE[*]} up -d)"; fi

# --- 2. application --------------------------------------------------------
BODY="$(curl -fsS --max-time 8 "http://127.0.0.1:${PORT}/" 2>/dev/null || true)"
if grep -q 'Photo Drop' <<<"$BODY"; then pass "home page answering (Photo Drop)"
else fail "home page did not answer on http://127.0.0.1:${PORT}/"; fi

# --- 3. diagnostics --------------------------------------------------------
PING1="$(curl -fsS --max-time 8 "http://127.0.0.1:${PORT}/ping.php" 2>/dev/null || true)"
if [[ -z "$PING1" ]]; then
    fail "/ping.php did not answer (P2S_DEBUG=1 in the compose?)"
    VERSION=""; ARCH=""; PID1=""
else
    PID1="$(sed -n 's/^pid=//p' <<<"$PING1" | head -n1)"
    VERSION="$(sed -n 's/^version=//p' <<<"$PING1" | head -n1)"
    ARCH="$(sed -n 's/^arch=//p' <<<"$PING1" | head -n1)"
    SAPI="$(sed -n 's/^sapi=//p' <<<"$PING1" | head -n1)"
    pass "ping.php: php=${VERSION:-?} sapi=${SAPI:-?} arch=${ARCH:-?} pid=${PID1:-?}"

    if [[ "$VERSION" == "8.5.11" ]]; then pass "vulnerable version (8.5.11)"
    else warn "version ${VERSION:-?} — the verified profile is php-8.5.11-bookworm-${ARCH:-amd64}"; fi

    PID2="$(curl -fsS --max-time 8 "http://127.0.0.1:${PORT}/ping.php" 2>/dev/null | sed -n 's/^pid=//p' | head -n1)"
    if [[ -n "$PID1" && "$PID1" == "$PID2" ]]; then pass "two requests served by the SAME process (pid=$PID1)"
    else fail "pid changed between requests ($PID1 -> ${PID2:-?}): Apache is not on 1 worker"; fi
fi

# --- 4. permissions inside the container ----------------------------------
if in_container -u 33 victim sh -c 'touch /var/www/html/.p2s-wtest && rm -f /var/www/html/.p2s-wtest' >/dev/null 2>&1; then
    pass "docroot writable by www-data (needed for the id>p1 proof)"
else
    fail "www-data cannot write to /var/www/html (run: sudo chmod 0777 ${ROOT}/app)"
fi

if in_container -u 33 victim sh -c 'touch /var/www/storage/.p2s-wtest && rm -f /var/www/storage/.p2s-wtest' >/dev/null 2>&1; then
    pass "storage writable by www-data (application uploads)"
else
    fail "www-data cannot write to /var/www/storage (run: sudo chmod 0777 ${ROOT}/storage)"
fi

# --- 5. Apache: 1 worker ---------------------------------------------------
# The behavioural proof is the identical pid twice (item 3). Here we only confirm
# the lab file is really mounted inside the container.
CONF="$(in_container victim grep -hE 'ServerLimit|MaxRequestWorkers' /etc/apache2/conf-enabled/zz-p2s.conf 2>/dev/null || true)"
if grep -qE 'ServerLimit[[:space:]]+1' <<<"$CONF" && grep -qE 'MaxRequestWorkers[[:space:]]+1' <<<"$CONF"; then
    pass "apache-lab.conf mounted (ServerLimit 1, MaxRequestWorkers 1)"
else
    fail "apache-lab.conf is not mounted with 1 worker (volume in docker/docker-compose.yml)"
fi

RUNCFG="$(in_container victim apache2ctl -t -D DUMP_RUN_CFG 2>/dev/null || true)"
if grep -qiE 'MaxRequestWorkers' <<<"$RUNCFG"; then
    printf '        %s\n' "$(grep -iE 'ServerLimit|MaxRequestWorkers' <<<"$RUNCFG" | tr '\n' ' ')"
fi

# --- 6. php.ini values the chain depends on --------------------------------
INI="$(in_container victim php -r 'echo implode("|", [ini_get("session.upload_progress.prefix"), ini_get("session.upload_progress.name"), ini_get("session.upload_progress.enabled"), ini_get("session.use_strict_mode"), ini_get("memory_limit"), ini_get("post_max_size"), ini_get("display_errors")]);' 2>/dev/null | tr -d '\r')"
I_PREFIX="$(cut -d'|' -f1 <<<"$INI")"
I_NAME="$(cut -d'|' -f2 <<<"$INI")"
I_ENABLED="$(cut -d'|' -f3 <<<"$INI")"
I_STRICT="$(cut -d'|' -f4 <<<"$INI")"
I_MEM="$(cut -d'|' -f5 <<<"$INI")"
I_POST="$(cut -d'|' -f6 <<<"$INI")"
I_DISP="$(cut -d'|' -f7 <<<"$INI")"

if [[ "$I_PREFIX" == "upload_progress_" ]]; then
    pass "session.upload_progress.prefix is the default (upload_progress_)"
else
    fail "session.upload_progress.prefix='${I_PREFIX}' — must stay 'upload_progress_', otherwise stage 1 (heap leak) misses every time"
fi

if [[ "$I_NAME" == "PHP_SESSION_UPLOAD_PROGRESS" ]]; then
    pass "session.upload_progress.name is the default (PHP_SESSION_UPLOAD_PROGRESS)"
else
    fail "session.upload_progress.name='${I_NAME}' — must stay PHP_SESSION_UPLOAD_PROGRESS"
fi

if [[ "$I_ENABLED" == "1" && "$I_STRICT" == "0" ]]; then
    pass "upload_progress enabled and session.use_strict_mode=0"
else
    fail "need session.upload_progress.enabled=1 and session.use_strict_mode=0 (got ${I_ENABLED}/${I_STRICT})"
fi

if [[ "$I_MEM" == "8M" && "$I_DISP" == "1" ]]; then
    pass "memory_limit=${I_MEM}, display_errors=On, post_max_size=${I_POST}"
else
    warn "memory_limit=${I_MEM:-?} display_errors=${I_DISP:-?} post_max_size=${I_POST:-?} — the verified profile is 8M / On / 512M"
fi

# --- 7. stager -------------------------------------------------------------
STAGER="$ROOT/app/stage/s"
if [[ -f "$STAGER" ]]; then
    LH="$(sed -n 's/^LHOST="\(.*\)"$/\1/p' "$STAGER" | head -n1)"
    LP="$(sed -n 's/^LPORT="\(.*\)"$/\1/p' "$STAGER" | head -n1)"
    if [[ -n "$LH" && "$LH" != "CHANGE_ME" ]]; then pass "stager: app/stage/s -> ${LH}:${LP}"
    else fail "stager has no Kali IP: run sudo ./install.sh --lhost <KALI-IP>"; fi
else
    fail "app/stage/s missing: run sudo ./install.sh --lhost <KALI-IP>"
fi

echo
if [[ $FAILS -eq 0 ]]; then
    echo "  All good. Target ready for the demo."
    IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    echo "  Kali: ./kali/p2s-run.sh --target http://${IP:-<ubuntu-IP>}:${PORT} --step proof"
    exit 0
fi

echo "  ${FAILS} check(s) failed — see docs/TROUBLESHOOTING.md"
exit 1
