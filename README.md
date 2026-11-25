# PHP2Shell — research, lab and exploit for CVE-2026-109619

Research material and the exploit built from scratch for the talk
**"Ghost in the Heap — Anatomy and Exploitation of CVE-2026-109619"** (OWASP Porto).

> For use against your own lab only. `lab/` runs disposable PHP 8.5.11 (vulnerable)
> and 8.5.12 (fixed) instances in Docker.

---

## What CVE-2026-109619 is

A stale-global-state flaw in the PHP interpreter: state owned by one request (error,
session, object, extension state) survives past that request while still pointing at
memory that has already been freed. A later request on the same worker consumes that
state before normal initialisation replaces it — a use-after-free with a path to
unauthenticated RCE.

- Official advisory: [GHSA-6wmf-4rv5-p3rp](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp)
- Sibling flaw (OOM/longjmp): [GHSA-w8hw-w9fx-j79w](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) — CVE-2026-109618
- Fixed in: PHP **8.2.35, 8.3.36, 8.4.27, 8.5.12** (2026-10-21)
- CVSS v4.0: 9.2 (`AV:N/AC:H/AT:P/PR:N/UI:N/VC:H/VI:H/VA:H`)

The distinction the talk explores:

| | CVE-2026-109618 | CVE-2026-109619 |
|---|---|---|
| Mechanism | `longjmp()` on OOM leaves request memory partially initialised | worker-global state outlives the request free |
| Where it hurts | shutdown of the *same* request (mod_php) | the *next* request on the same worker |
| Role in our exploit | arms the state / forces the interruption | UAF, leak and control-flow primitive |

---

## Repository layout

```
.
├─ README.md                  # this file
├─ STATUS.md                  # what is done, verified and missing
├─ docs/
│  ├─ 00-vulnerability-brief.md   # versions, timeline, impact, mitigations
│  ├─ 01-advisory-map.md          # producer/consumer model mapped to the source
│  ├─ 02-exploit-design.md        # the exploit architecture, stage by stage
│  └─ 03-talk/
│     ├─ abstract.md              # title + abstract for the CFP
│     ├─ outline.md               # minute-by-minute run sheet
│     └─ demo-runbook.md          # live demo checklist
├─ lab/
│  ├─ docker-compose.yml          # 8.5.11 (target) / 8.5.12 (control)
│  ├─ php/{vuln,fixed}.ini        # explicit, reproducible configuration
│  └─ www/index.php               # minimal victim: no vulnerable code inside
├─ exploit/
│  ├─ php2shell.py                # CLI: fingerprint | arm | probe | leak | run
│  ├─ p2s/                        # exploit library
│  └─ tests/                      # transport smoke tests (no PHP needed)
└─ research/                      # sources, notes, captures
```

## Quickstart

```bash
# 1. lab (Docker on Linux/macOS; on Windows it needs Docker Desktop + WSL2)
cd lab && docker compose up -d

# 2. confirm the target and its version
python exploit/php2shell.py fingerprint --url http://127.0.0.1:8511

# 3. stages
python exploit/php2shell.py arm    --url http://127.0.0.1:8511
python exploit/php2shell.py probe  --url http://127.0.0.1:8511
```

## Status

See [`STATUS.md`](STATUS.md). Nothing in this repository should be read as "it works"
without the matching evidence recorded under `research/`.

## License

MIT — see `LICENSE`.
