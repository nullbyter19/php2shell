# Advisory → source map

Goal: turn the prose of GHSA-6wmf-4rv5-p3rp into concrete points in the PHP source, so
the talk can show them on screen with path and line.

> Every line number has to be checked against the tag in question
> (`php-8.5.11` = vulnerable, `php-8.5.12` = fixed) before it goes on a slide.

## 1. The producer/consumer model

```
  request N                                     request N+1 (same worker)
  ─────────                                     ──────────────────────────
  [producer]                                    [consumer]
  operation publishes       ──►  worker global ──►  reads before normal init
  request state into a global   (pointer)           → UAF / branch / dtor
        │
        ▼
  fatal error interrupts
  before the reset
        │
        ▼
  request heap is freed
  (the global still points at it)
```

Conditions (advisory §Vulnerability):
1. a reachable producer stores request state where the next request can reach it;
2. the reset is missed, or state is repopulated after it;
3. the request heap is freed while the global is still live;
4. the same worker serves the next request;
5. the consumer runs before normal init.

## 2. Producers to verify in the source

| # | Producer | Code to confirm | Why it matters |
|---|---|---|---|
| P1 | fatal error backtrace (8.5) | `Zend/zend.c` — backtrace stored on fatal error | basis of the confirmed mod_php case |
| P2 | OOM during multipart parsing | `main/rfc1867.c` + `Zend/zend_alloc.c` (`longjmp`) | CVE-109618; also arms session state |
| P3 | `Maximum execution time exceeded` | `Zend/zend_execute_API.c` | interruption the attacker can control |
| P4 | warning during shutdown (post-deactivation) | extension cleanup / `php_request_shutdown` | repopulates error state that was already cleared |

## 3. Consumers to verify

| # | Consumer | Code | Prerequisite |
|---|---|---|---|
| C1 | diagnostic/INI applied before `php_request_startup()` | `main/main.c`, `sapi/apache2handler/sapi_apache2.c` (mod_php: `.htaccess`, `php_value`) | mod_php; invalid or deprecated INI value |
| C2 | `session.upload_progress` | `ext/session/session.c` (`rfc1867` handler, `PS(id)`, `PS(http_session_vars)`) | `session.upload_progress.enabled=On` (default) |
| C3 | unserialize state read | `ext/standard/var_unserializer.re`, `BG(unserialize)` | depends on the application flow |

Advisory note: with mod_php, the producer and the fatal error can both happen during
multipart startup. Under FPM the child exits when startup fails, so the validated FPM path
publishes state **during application execution** and uses upload progress as the early
consumer.

## 4. The patch

- The full patch touches roughly 300 files (state resets in `main/main.c`, `Zend/zend.c`,
  `Zend/zend_execute_API.c`, `Zend/zend_hash.c`, `ext/session/session.c`,
  `ext/standard/basic_functions.c`, `main/rfc1867.c`, `Zend/zend_alloc.c`, OPcache).
- CVE-109618: removes `longjmp()` on OOM; replaces it with a delayed "soft OOM" at a VM
  safe point and a "hard OOM" using `_exit()` above a second threshold.
- CVE-2026-109619: resets state before any early consumer (`php_basic_early_rinit()` before
  `rfc1867`), and widens the reset to error/object/extension state.
- Relevant regression tests (`sapi/cli/tests/oom_request_parsing_next_request.phpt`,
  `oom_shutdown_function_next_request.phpt`, `ext/session/tests/rfc1867_no_user_code.phpt`,
  `rfc1867_incomplete_class_reserved_props.phpt`).

### How to use this in the talk

"Before/after" slides with two or three hunks: the `longjmp` that disappears, the reset
that now happens before `rfc1867`, and the `BG(unserialize)` reset. That is the part that
makes the audience understand this is not "one `free()` too many".

## 5. What the advisory does NOT say

Good material for the talk, because it shows method rather than regurgitation:

- It gives no offsets, no heap layout, no per-build success rate.
- It does not fix a single chain: it says "multiple strategies"; choosing producer and
  consumer is our job.
- It does not promise portability: "exploit portability and reliability depend on the PHP
  build, extensions, frontend behavior and allocator layout".
- It does not clear FrankenPHP or LSAPI: "did not establish" is not "immune".

## 6. Open questions (to investigate in the lab)

1. With `session.upload_progress` as the consumer, how many requests until the worker
   reuses the chunk? (depends on `MaxRequestWorkers`, `pm.max_requests`.)
2. Which Zend MM chunk class does `PS(id)` occupy, and which multipart field reclaims it
   deterministically?
3. Is `fatal_error_backtraces` on by default in 8.5.11? If so, path P1 is a default path.
4. Is the `Set-Cookie` leak stable with `session.use_strict_mode=1`?
5. Under FPM the validated path needs an application operation — what is the minimum
   viable one (a route that calls `session_start()` with a large session)?
