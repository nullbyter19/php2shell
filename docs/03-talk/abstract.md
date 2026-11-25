# Talk — OWASP Porto

> Working document for the CFP submission: title, abstract, short variants for the
> form, and the scoping notes for the live demo.

---

## Title

**Ghost in the Heap — Anatomy and Exploitation of CVE-2026-109619 (PHP2Shell)**

*Subtitle: One POST, zero credentials, and a request that died before it could forget itself.*

### Alternatives

| # | Title | Tone |
|---|-------|------|
| B | **The Request Is Dead, the Global Isn't** — 14 years of stale state in PHP | Narrative, "why" first |
| C | **PHP2Shell: A Shell Without Touching Application Code** | Direct, impact first |
| D | **From Advisory to `id`** — Building a PHP UAF Exploit, Step by Step | Teaching, method first |

Recommendation: option A for the poster (it is memorable and says what it is), with the
subtitle from option D in the event description, because that is what separates this
from "another talk about this week's CVE".

---

## Abstract

On 21 October 2026, PHP shipped an emergency release for two memory-corruption flaws in
the interpreter itself: CVE-2026-109618 and CVE-2026-109619, collectively known as
**PHP2Shell**. This is not a framework, plugin or application-code bug. It is the engine
behind most of the web handing remote code execution to anyone who sends the right HTTP
request — no authentication, no session, not a single line of vulnerable PHP on the
victim side.

This talk dissects **CVE-2026-109619** from the source. We follow a request's lifecycle
to the point where a fatal error abandons an operation midway, leaving worker-global
state — session, unserialize state, error backtrace — pointing at memory that has already
been freed. The next request consumes that stale state *before* normal initialisation
replaces it. That is a use-after-free across two requests in the same process, and the
official advisory models it as a **producer → consumer** pair. We will watch that pair
happen, line by line, with the code on screen.

Then we build the exploit live, from scratch:

1. fingerprinting the target and pinning the worker (the same process has to serve both requests);
2. the **producer**: multipart `session.upload_progress` publishes state, then an OOM or fatal error skips the reset;
3. the **consumer**: the next request reading stale state before initialisation;
4. turning that read into a **heap and `libphp` base leak** that defeats ASLR;
5. **heap grooming** to reclaim the freed chunk with attacker-controlled data;
6. hijacking a `zval_ptr_dtor` into `zif_system` to run a command as the worker.

We close with what defenders actually need: the 8.5.12 patch diff and what each piece
changes; why `session.upload_progress.enabled=Off` reduces but does not fix it; why
`error_reporting`, `@` and `display_errors` give you nothing here; and how to tell a
compromised worker from a slow one in your logs.

All code is written from scratch for this talk and released on GitHub together with the
Docker lab, so anyone can reproduce it. The demo runs against the local lab only — no
third-party targets.

**Audience:** PHP developers, pentesters, SRE/blue team.
**Level:** intermediate to advanced (C, memory management, low-level HTTP).
**Duration:** 40 minutes + 10 for questions.

---

## Short variants

**60 words (CFP form):**

> CVE-2026-109619 leaves a PHP worker's global state pointing at freed request memory. The
> next request reads that state before it is replaced. We follow the producer/consumer
> pair through the PHP source and build the full exploit live: ASLR leak, heap grooming,
> and command execution from a single unauthenticated POST.

**One line (poster):**

> The request is over. The memory is freed. The global is still pointing at it.

---

## Demo scoping notes (not for the CFP)

- The "shell" promise depends on the exploit being functional in the lab. Current state:
  see `STATUS.md` at the repository root. If the final stage is not stable by the time of
  the talk, the demo becomes (a) producer trigger, (b) UAF confirmed under ASAN,
  (c) ASLR leak, with the control-flow stage on video. The abstract stays honest if we
  change "run a command" to "control execution flow".
- Never present third-party reliability numbers as ours. If we quote the advisory (9.2
  CVSS, "confirmed RCE against mod_php"), we cite the source on the slide.
- The lab is local and disposable; the demo touches no third-party infrastructure and
  nothing on the venue network.
