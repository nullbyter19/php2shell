# Run sheet — 40 minutes

| Min | Block | Content | Support |
|---|---|---|---|
| 0–3 | Hook | "This request has no vulnerable PHP in it. It still gives a shell." A 30-second demo against the lab: `id` in the response. | terminal, 8.5.11 target |
| 3–6 | Context | What PHP2Shell is, why two CVEs, what the advisory says and does not say. The 20–21 Oct timeline. | timeline slide |
| 6–10 | The model | Request-owned state vs worker-owned state. The producer→consumer diagram. Why the free is not the end of the story. | diagram |
| 10–16 | Anatomy of 109619 | Lifecycle: `php_request_startup` → `rfc1867` → `zend_activate_modules` → `RINIT`. Where the consumer jumps ahead of init. `session.upload_progress` and `fatal_error_backtraces`. | `ext/session/session.c`, `main/main.c` |
| 16–20 | The producer | A fatal error midway through an operation; the reset that never runs; the warning that repopulates after the reset. Demo: arm it and watch the worker go "dirty". | terminal + gdb |
| 20–26 | The consumer | The next request reading memory that belonged to another request. ASAN firing. Why `error_reporting`/`@` do not help. | ASAN output |
| 26–32 | From UAF to shell | Heap and `libphp` leak via `Set-Cookie`; heap grooming; `zval_ptr_dtor` → `zif_system`. What is engineering and what is luck. | exploit running |
| 32–36 | Patch | Before/after in three hunks: `longjmp` gone, reset before `rfc1867`, widened reset. What the patch closes and what stays fragile. | diff |
| 36–39 | Defence | What works (patch), what reduces (upload_progress off, `fatal_error_backtraces=0`, `pm.max_requests`), what is theatre (`display_errors=Off`). Detection in logs. | table |
| 39–40 | Close | "Fourteen years of code, one missing reset line." Repo + lab + credits. | QR to GitHub |

## Key messages (what the audience must leave with)

1. **Request memory is not worker memory.** The bug lives on the boundary, and that
   boundary is C code, not application code.
2. **Producer and consumer are two requests.** That changes the detection model: no single
   request is "the attack".
3. **Silencing the error does not close the path.**
4. **The patch is a state reset, not an extra `free`.**
5. **Writing the exploit is what separates "I read the advisory" from "I understood it".**

## Likely questions (and short answers)

- *"Is this only mod_php?"* — No. FPM is conditionally exposed; the validated path uses
  upload progress as the consumer and needs an application operation.
- *"Does a WAF fix it?"* — It helps with known variants; the advisory explicitly says there
  is no generic configuration mitigation. It is not an architecture answer.
- *"What about PHP 7.4?"* — EOL, no official release; backports exist on dedicated branches.
- *"Is the exploit yours?"* — Yes, written from scratch for this talk; lab and code are on GitHub.
- *"What is the reliability?"* — Give the number measured in our lab, with conditions, and
  never extrapolate it to someone else's production.

## Material to produce

- [ ] Slides (17–20)
- [ ] Producer/consumer diagram (one image, reused 3x)
- [ ] Backup recording of every demo (plan B if wifi/Docker fails)
- [ ] Public repo + `owasp-porto` tag
- [ ] QR code to the repo
