# 6.7.12 changes that stop existing programs compiling (or change what they do) beyond the decisions' text — confirm each, or restore it — OPEN

**Status:** 🟡 **OPEN** — a confirmation for the user, collected 2026-10-15 by the 6.7.12 release-docs pass (the lane drafts
re-measured on the merged tree). Each item shipped in 6.7.12 and is in CHANGELOG [6.7.12] / ecosystem-migration § 6.7.12.
Same shape as `archived/2026-10-14-6711-behaviour-changes-beyond-the-decisions-text.md` (all kept, 2026-10-15).
**Placement:** 6.7.13 — repair 3: struct values (fixfirst lane; filed from the 6.7.12 release-docs pass, 2026-10-15) — never 7.x.
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
