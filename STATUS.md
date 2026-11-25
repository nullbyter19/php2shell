# Project status

Updated: 2026-10-26

Legend: ✅ done and verified · 🟡 done, not verified · ⬜ pending

## Documentation and talk

| Item | Status | Note |
|---|---|---|
| Title + abstract (`docs/03-talk/abstract.md`) | ✅ | 4 title options, long and short abstracts |
| 40-minute outline (`docs/03-talk/outline.md`) | ✅ | includes likely Q&A |
| Demo runbook (`docs/03-talk/demo-runbook.md`) | ✅ | recording as plan B |
| Technical brief (`docs/00-vulnerability-brief.md`) | ✅ | with citable sources |
| Advisory → source map (`docs/01-advisory-map.md`) | 🟡 | exact line numbers still to confirm against the tags |
| Exploit design (`docs/02-exploit-design.md`) | ✅ | specification of the seven stages |
| Slides | ⬜ | next block of work |

## Lab

| Item | Status | Note |
|---|---|---|
| `docker-compose.yml` (8.5.11 / 8.5.12) | 🟡 | written; **never executed** (host has no Docker) |
| target / control / asan ini files | ✅ | vuln.ini and fixed.ini are identical by design |
| mpm_prefork with a single worker | ✅ | makes the demo deterministic |
| `www/index.php` (victim with no vulnerable code) | ✅ | `<?php echo 'ok';` |
| `www/pid.php` (worker debugging) | ✅ | disabled unless `P2S_DEBUG=1` |
| ASAN build (`lab/asan/`) | 🟡 | experimental Dockerfile, never built |

## Exploit

Transport and CLI **✅ verified** on 2026-10-26: `python exploit/tests/test_transport.py`
→ 17/17 (Content-Length, chunked, unframed body, keep-alive on the same source port,
well-formed multipart, pointer parser, version table, end-to-end CLI against a mock
server). This proves the plumbing, **not** the vulnerability.

| Stage | Status |
|---|---|
| S0 fingerprint | 🟡 implemented, never run against real PHP |
| S1 worker pinning | 🟡 implemented (assumes a single-worker lab; real targets are probabilistic) |
| S2 arming (producer) | 🟡 session / no-length / nested / headers variants |
| S3 probe (consumer) | 🟡 advisory markers implemented, never observed |
| S4 leak | 🟡 candidate extraction ✅; offset calibration ⬜ |
| S5 grooming | ⬜ specified |
| S6 control flow | ⬜ specified; blocked on binary offsets |

## Known blockers

1. **Host has no Docker, PHP or WSL distro.** The lab cannot run here. Options:
   Docker Desktop + WSL2, a Linux machine, or a VM.
2. **Offsets**: S6 does not work without deriving offsets from the real lab binary.

## Repository rule

Nothing moves from 🟡 to ✅ without evidence under `research/captures/`. No capture, no ✅.

## Log

| Date | Check | Result |
|---|---|---|
| 2026-10-26 | transport + CLI suite (`exploit/tests/test_transport.py`) | 17/17 |
| 2026-10-26 | Docker lab | not executed: host has no Docker/WSL |
