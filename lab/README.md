# Lab

Two instances with identical configuration and different versions:

| Service | Image | Port | Role |
|---|---|---|---|
| `victim-vuln` | `php:8.5.11-apache` | 8511 | target (vulnerable) |
| `victim-fixed` | `php:8.5.12-apache` | 8512 | control (fixed) |
| `victim-asan` | local ASAN build | 8513 | see the UAF (profile `asan`) |

Both run a **single prefork worker** (`apache/mpm_prefork.conf`) so the producer and the
consumer land on the same process. That is what makes the demo deterministic — and it is
exactly what you do not control on a real target.

## Start

```bash
docker compose up -d
docker compose ps
curl -s http://127.0.0.1:8511/    # ok
curl -s http://127.0.0.1:8512/    # ok
curl -s http://127.0.0.1:8511/pid.php   # pid=… sapi=apache2handler
```

## Sanity checks

```bash
# version and SAPI
docker compose exec victim-vuln php -v
docker compose exec victim-vuln apache2ctl -M | grep php

# effective ini (must show ours)
docker compose exec victim-vuln php -i | grep -Ei 'upload_progress|fatal_error_backtraces|memory_limit'
```

## Requirements

- Docker with Compose v2.
- On Windows: Docker Desktop with the WSL2 backend (the current host has neither Docker nor
  a WSL distro).
- The `php:8.5.11-apache` / `php:8.5.12-apache` tags must exist in the official registry.
  If 8.5.10 is the newest available, adjust the tags and record the difference in
  `STATUS.md` — never pretend you tested the version you did not test.

## Cleanup

```bash
docker compose --profile asan down -v
```

## Warning

This lab contains deliberately vulnerable software. It is bound to `127.0.0.1` and must
never be exposed to any network.
