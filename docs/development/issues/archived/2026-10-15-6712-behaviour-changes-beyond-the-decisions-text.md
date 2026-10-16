# 6.7.12 changes that stop existing programs compiling (or change what they do) beyond the decisions' text — confirm each, or restore it — RESOLVED

> ✅ **RESOLVED in v6.7.13** (TL-15 – TL-19, with the review fix TL-18r, under the user's decisions of 2026-10-15. Item 1 (D36, keep): `EPOLL_EVENT_SIZE` stays a `const`. No code; epoll_event_readers.tcyr and the two gates are green. Item 2 (D37, keep): 6.7.12's D23 reach stays. lib/result.cyr's `ok_via` and `err_via` are now declared `: Result`, so `cyrius header lib/result.cyr` gives rc 0 with both `cyr_val2`. Callers are byte-identical over a 3,320-compile differential (x86_64, aarch64, cx, PE). The folds' `: i64` wrappers stay refused until their own patches. Item 3 (D38, keep): `cyrius update` writes what `lib sync` writes. No code; `cli_path_reporting_leftovers.sh` R6a–R6c are green. Item 4 (D39, restore): after its cleanup the CLI resets the signal to SIG_DFL, re-raises it and unblocks it. So it dies by the signal again: WIFSIGNALED / WTERMSIG N, 6.7.11's wait status. `$?` is still 128+N, and `exec_capture_status` gives st = (143, 1). Rows: `crossos/cli_kill_handler.tcyr` 38/38 on x86_64, qemu-aarch64, pi, ecb and ach (the 6.7.12 handler fails 11), and `cli_temp_dir_no_leak.sh` axis 7's cyrius-parent row (`143 1`; 6.7.12's CLI gives `143 0`). Item 5 (D40, keep): the top-level `rd(mkv(..))` refusal stays, now pinned on aarch64, cx and PE (`simd_pointer_param.sh` Y13a / Y13c / Yw2d). A correction to item 5: 6.7.11 compiled it to a fault on x86_64 too (139); only 6.7.10's x86_64 refused it. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — a confirmation for the user, collected 2026-10-15 by the 6.7.12 release-docs pass (the lane drafts
re-measured on the merged tree). Each item shipped in 6.7.12 and is in CHANGELOG [6.7.12] / ecosystem-migration § 6.7.12.
Same shape as `archived/2026-10-14-6711-behaviour-changes-beyond-the-decisions-text.md` (all kept, 2026-10-15).
**Placement:** 6.7.13 — repair 3: struct values (closures lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D36 — Keep (const) · D37 — Keep · D38 — Keep · D39 — clean up, then die by the signal (as before 6.7.12; $? still 128+N) · D40 — Keep (refused by name).
**Severity:** Medium — code that compiled on 6.7.11 stops compiling, or a tool / CLI result changes; none miscomputes.

## Items (keep — the item closes — or restore 6.7.11)

1. **`EPOLL_EVENT_SIZE` is a `const`** (LIB-5): a program that declares its own `EPOLL_EVENT_SIZE` after including
   `lib/syscalls.cyr` stops compiling ("const … declared twice"), as does a build that includes two syscall peers (their
   same-name vars only warned). The issue proposed a `var`; the brief said no decision was needed.
2. **D23's reach** (TL, `cyrius header`): D23 named an UNANNOTATED pair return; the lane also refuses a fn annotated with
   a word type (`: i64`) whose body returns a stack-enum pair — `cyrius header` now exits 1 on `lib/result.cyr`
   (`ok_via` / `err_via`) and on sources of bayan, mabda, sigil, vani and yukti (14 headers rc 0 → 1 in the lane's census).
3. **D18's reading** (TL, `cyrius update`): update writes `lib sync`'s declared set (declared leaves + per-OS peers +
   test-scope leaves, no include walk); its `../cyrius/lib` and `$CYRIUS_HOME/current` fallbacks are gone.
4. **The CLI exits `128+N` on a fatal signal** (TL-24): it exits through `exit(128+N)` (WIFEXITED) instead of dying by
   the signal, so a shell's SIGINT loop-stop no longer fires on it. From the issue's own option text; no decision named it.
5. **D27 at top level** (FX-1): `rd(mkv(..))` at top level is refused ("returns a vector by value … call it inside a fn")
   — no frame for the temporary, the struct rule; on aarch64 / cx / PE it compiled (to a fault) on 6.7.11.
