# Troubleshooting — PHP2Shell lab (Ubuntu + Kali)

Order the problems by what you see, not by what you suspect. Each item below has
a quick test and the probable cause.

---

## 1. The target does not respond

```bash
curl -v http://192.0.2.20:8080/
```

| Symptom | Check |
|---------|-------|
| `Connection refused` | Container stopped: `cd docker && sudo docker compose ps` |
| `Connection timed out` | Network: `ping 192.0.2.20`, and whether both VMs are on a **bridge** (NAT isolates Kali) |
| Works on Ubuntu, not from Kali | `ufw`: `sudo ufw status`; if active, `sudo ufw allow 8080/tcp` |
| 403/404 at the root | Volume did not mount: `docker compose logs --tail 50` |

On Ubuntu, test from inside the container network:

```bash
sudo docker exec p2s-ubuntu-victim curl -s http://127.0.0.1/ | head -5
```

---

## 2. `CONFIG BLOCKED` in the pre-flight check

The toolkit warns when `post_max_size` would make PHP reject the body before
parsing it. It is the most common and most annoying error, because it looks like
an exploit failure.

```bash
sudo docker exec p2s-ubuntu-victim php -i | grep -E 'post_max_size|memory_limit|display_errors'
```

Expected:

```
memory_limit => 8M => 8M
post_max_size => 512M => 512M
display_errors => On => On
```

If the values do not match, `php.ini` was not mounted. Check the volume in
`docker/docker-compose.yml` and restart:

```bash
sudo docker compose down && sudo docker compose up -d
```

> Rule: `post_max_size` ≥ `memory_limit` + 12M.

---

## 3. Different worker between the two requests

Symptom in `p2s-run.sh`:

```
!! worker changed between requests (41 -> 42)
```

The stale state lives in the worker. If Apache swaps process between the
producer and the consumer, there is nothing to consume.

1. Confirm the effective Apache config (it must be 1/1):
   ```bash
   sudo docker exec p2s-ubuntu-victim apache2ctl -t -D DUMP_RUN_CFG | grep -E 'ServerLimit|MaxRequestWorkers'
   ```
2. If it shows 150 (the image default), `apache-lab.conf` was not mounted.
   Check the volume in `docker/docker-compose.yml` and recreate the container:
   ```bash
   cd docker && sudo docker compose down && sudo docker compose up -d
   ```
3. `MaxConnectionsPerChild` must be `0`: recycling the child kills the state.
4. If it still alternates, check whether there is **another** Apache on the same
   port (`sudo ss -ltnp | grep 8080`) or whether you are talking to the old lab.

---

## 4. The chain failed and now nothing works

Normal: stage 3 kills the Apache child that executed `zif_system`. The master
respawns it, but the heap state is left dirty.

```bash
cd ~/ubuntu-lab/docker && sudo docker compose restart
```

And repeat. The first run after a restart is the most reliable one — on stage,
restart between attempts instead of insisting three times.

---

## 4b. `HEAP_LEAK_FAILED` on EVERY attempt

Symptom: `stage 1: heap leak (attempt 1/3)` ... `[-] heap leak missed` three
times, ending in `HEAP_LEAK_FAILED`. If this happens every time — not once — it
is not a dirty heap: it is configuration. Stage 1 depends on the session key
being `upload_progress_` + the field value, that is, on the **default prefix**.

Check inside the container:

```bash
docker exec p2s-ubuntu-victim php -r \
  'echo ini_get("session.upload_progress.prefix"), PHP_EOL, ini_get("session.upload_progress.name"), PHP_EOL;'
```

Expected:

```
upload_progress_
PHP_SESSION_UPLOAD_PROGRESS
```

If the prefix shows up as `PHP_SESSION_UPLOAD_PROGRESS`, `php.ini` was changed by
mistake (`prefix` is not the same thing as `name`). The key becomes 23 bytes
longer, the serialized data changes size and the leak never lines up. Fix it by
removing the line from `docker/php.ini` and restart:

```bash
cd ~/ubuntu-lab/docker && sudo docker compose restart
cd .. && sudo ./verify.sh     # check 6 verifies these values
```

If the prefix is correct, the problem is **heap geometry**: the profile was
measured on another heap. Two known causes:

1. `opcache.enable = 0` in `docker/php.ini`. The official image already starts
   with OPcache active (`docker-php-ext-enable opcache`) and the
   `php-8.5.11-bookworm-amd64` profile was calibrated in that state. Without
   OPcache, `index.php` is compiled **on the request heap**, the startup heap
   changes and stage 1's field N stops landing in the right block. Fix:
   `opcache.enable = 1` and recreate the container (`down` + `up -d`; `restart`
   keeps the old inode of the single-file mount).
2. Image different from the calibrated one (rebuilt tag, another base). Then the
   whole profile is worthless: measure it again against the live target, without
   docker:

   ```bash
   cd ~/PHP2Shell/ubuntu-lab/kali
   ./p2s-stage1-probe.py --target http://192.0.2.20:8080 --write-profile
   # or through the driver itself:
   ./p2s-run.sh --target http://192.0.2.20:8080 --step proof --calibrate
   ```

   The probe repeats the toolkit calibrator's requests, finds out which field
   (`vNNNN`) takes the stale block, tries the forge lengths and writes
   `P2S_STAGE1_N` / `P2S_FORGE_LEN` into the profile (`.bak` backup).

---

## 4c. `/` returns 403 and `/ping.php` 404

Apache is up but the docroot is empty: the `../app` bind mount in
`docker-compose.yml` did not resolve to a directory containing the application.

```bash
cd /opt/PHP2Shell && ls -la ubuntu-lab/app       # index.php, ping.php, ...
```

* Empty directory and `git status` showing the files as deleted:
  `git checkout -- ubuntu-lab/app`
* Old clone, without those files: `git pull`
* Afterwards: `cd ubuntu-lab/docker && sudo docker compose down && sudo docker compose up -d`

---

## 5. `profile not found` / architecture refusal

```
[!] no profile for php-8.5.11
```

* The profile is `php-8.5.11-bookworm-amd64`. If you are on ARM (Apple Silicon,
  Graviton), use the matching aarch64 profile and `--arch aarch64`.
* For a remote target, `--arch` is **required** (HTTP does not expose the CPU).
* To see the options and the exact profile names:
  ```bash
  python3 ~/tools/php2shell/tools/php2shell_auto.py --help
  ```

---

## 6. "Fixed release" in detection

If the fingerprint says 8.5.12, the container came up with the wrong image:

```bash
sudo docker inspect p2s-ubuntu-victim --format '{{.Config.Image}}'
curl -s http://192.0.2.20:8080/ping.php
```

`ping.php` shows `php=` directly. It must be `8.5.11`.

---

## 7. The stager does not open the shell

Test on Ubuntu, from inside the container, as if you were www-data (with the
Kali listener already open):

```bash
sudo docker exec -u 33 p2s-ubuntu-victim sh /var/www/html/stage/s
sudo docker exec p2s-ubuntu-victim cat /tmp/p2s-stager.log
```

The stager writes the same record in two places:

* `/tmp/p2s-stager.log` — inside the container, read with `docker exec`;
* `/var/www/html/p2s-stage.log` — in the docroot, which Kali reads over HTTP:
  `curl -s http://<target>:8080/p2s-stage.log`

| Symptom | Cause |
|---------|-------|
| `no such file` | `install.sh` did not run or you used `--purge` |
| `connect-fail` in the log | Listener was not open **before** the trigger |
| `connect-ok`, no prompt on Kali | the listener accepted and closed: look at its tab, not at the target |
| Log does not exist | wrong IP in the stager or the execution never reached it: `head -15 app/stage/s` |
| `bash missing` in the log | image without `/bin/bash` — use the compose image, it ships bash |
| `BLIND STEP` in `p2s-run.sh` | stager from the old `install.sh` (no `/p2s-stage.log`): run the install again |

Re-running `install.sh` rewrites the stager with the right IP:

```bash
sudo ./install.sh --lhost 192.0.2.10 --lport 4444
```

---

## 8. You got in without a shell, but with `uid=33(www-data)`

That is success, not failure. It means:

* the RCE worked (step 1);
* `sh stage/s` was executed, but the connection back did not complete.

Check the listener, the `ufw` on Kali (outbound is not blocked, but `ncat` must be
listening on `0.0.0.0`, not on `127.0.0.1`) and whether the IP in the stager is
Kali's on the right network (`ip -br a`).

---

## 9. "No proof" is not "no execution"

PHP's `system()` returns no body: when the command is `sh stage/s`, the toolkit
ends with `EXPLOIT_FAILED (no proof; the command may still have executed blind)`
even when the reverse shell opened. That verdict was never proof of failure — and
`p2s-run.sh` does not use it on the shell step. It reads the stager log
(`/p2s-stage.log`, written by the current `install.sh`) and decides on its own:

| Verdict | Meaning | Exit |
|---------|---------|------|
| `SHELL OK` (green) | the stager ran and the listener accepted the TCP connection | 0 |
| `CALLBACK REFUSED` (amber) | RCE confirmed; the listener was not up | 5 |
| `RCE OK · CALLBACK NOT CONFIRMED` (amber) | new log, but no connect line | 0 |
| `BLIND STEP (old stager)` (amber) | stager without instrumentation: HTTP neither confirms nor denies | 0 |
| `UNDEFINED (Apache not answering)` (amber) | the chain killed the worker before the log | 0 |
| `NOT EXECUTED` (red) | stager instrumented and no new line | 4 |

`BLIND STEP` means the target still has the stager from the old `install.sh`,
which only wrote inside the container. Run the installer again on Ubuntu (it
rewrites `app/stage/s`) and the verdict becomes automatic:

```bash
sudo ./install.sh --lhost <kali>
```

If the `id>p1` of step 1 does not come back, then the chain did fail — and the
toolkit itself shows the attempts (`stage 3 attempt N no proof yet`). Container
detail when you need it:

```bash
sudo docker logs --tail 80 p2s-ubuntu-victim
```

Quick diagnostic before going on stage:

```bash
./kali/p2s-diag3.py --target http://192.0.2.20:8080
```

---

## 10. Docker on Ubuntu

```bash
sudo systemctl status docker
sudo docker info | head -20
```

* `permission denied /var/run/docker.sock` → `sudo usermod -aG docker $USER` and
  open the session again (or use `sudo docker`).
* `docker compose` does not exist → install `docker-compose-v2`.
* Out of space: `df -h`; the PHP image plus build cache eat a few GB.

---

## 11. Event network

* If Kali is **physical** and Ubuntu is a VM, use **bridge**. NAT does not let
  the container open a connection back to your host predictably.
* Test the return path before the talk:
  ```bash
  # on Kali
  nc -lvnp 4444
  # on Ubuntu
  curl -s telnet://192.0.2.10:4444 </dev/null || true
  ```
* Event Wi-Fi with client isolation breaks the reverse shell. Have your own AP or
  cable. This is reason number 1 for shell demos dying at conferences.
