# Win64 PE `syscall()` reroute only fires for a compile-time-literal number — a variable number silently emits a non-functional raw `syscall` — RESOLVED (v6.1.16)

> **RESOLVED v6.1.16.** Non-literal syscall numbers under `_TARGET_PE` now emit a
> runtime dispatch (`EPE_SYSCALL_DYNAMIC`, `src/backend/x86/emit.cyr`): a
> `cmp`/`jne` switch on the number over the routable POSIX syscalls of the
> call-site arity, branching to the same `E*_PE` sequence the literal path uses;
> an unknown number at a routable arity returns `-38` (`-ENOSYS`) instead of the
> silent-no-op `0F 05`. A var-number call whose arity matches no routable syscall
> is now a hard compile error rather than a miscompile. Verified on real `cass`:
> the T1–T4 repro (`repros/2026-06-09-pe-var-syscall-T1-T4.cyr`) now writes all
> four lines (T3/T4 were silent before). NOTE: `nanosleep(35)` is still not
> routed (a separate pre-existing gap — returns honest `-38` now); sakshi's
> default stderr path (`write`+`clock_gettime`) is fully functional.

**Discovered:** 2026-06-09 while integrating sakshi structured logging into the ai-hwaccel Windows PE wheel (2.3.9).
**Reporter:** ai-hwaccel v2.3.8→2.3.9 (consumer) / sakshi v2.2.2 (the concrete victim — `src/syscalls.cyr`).
**Cyrius version at time of report:** 6.1.15 (cycc_win).
**Severity:** **High.** Silent total output loss on a tier-1 target. No diagnostic at the *write site*; the program runs, exits 0, and produces nothing — the worst failure mode. Any consumer that holds a syscall number in a variable (the portable arch-dispatch idiom) gets a binary that looks fine and logs nothing on Windows.
**Affects:** `_TARGET_PE == 1` codegen, `src/frontend/parse_expr.cyr` syscall lowering. x86-Linux / aarch64 / macOS unaffected (their reroutes have the same literal dependence, but Linux uses the real `syscall` instruction so a variable number still works there).

## Summary

cyrius's PE syscall reroute (`syscall(1,fd,buf,len)` → `GetStdHandle+WriteFile`, etc.) is a **compile-time pattern match on a constant-folded first argument**. When the syscall *number* is a runtime value (e.g. a global `var`), the fold fails, no case matches, and lowering falls through to the generic path that emits the x86_64 `syscall` instruction (`0F 05`) — a Linux-only encoding. On Windows that instruction either faults (`STATUS_ILLEGAL_INSTRUCTION`) or, depending on the value left in `rax`, invokes an arbitrary NT syscall that returns an error without crashing. For `rax=1` (write) it returns silently, so the call is a **silent no-op**: no bytes written, no fault, exit 0.

The second argument (fd) may be a variable — only the **number** must be literal. Confirmed on real hardware (`cass`, Windows 10.0.26200, x86_64):

| call | number | fd | reaches stderr on `cass`? |
|------|--------|-----|---------------------------|
| `syscall(1, 2, "T1\n", 3)` | literal | literal | ✅ |
| `syscall(1, fd2, "T2\n", 3)` | literal | **var** | ✅ |
| `syscall(w, 2, "T3\n", 3)` | **var** | literal | ❌ silent |
| `syscall(w, fd2, "T4\n", 3)` | **var** | var | ❌ silent |

(`var w = 1; var fd2 = 2;`) — only the literal-number rows write. The compiler emits the generic *"syscall(n,…) routes n=… others crash"* warning for exactly the two var-number sites (T3, T4) and **not** for the literal sites — so the compiler already knows it can't analyze them, it just can't reroute them and produces a non-functional binary anyway.

### Real-world impact

sakshi (the AGNOS structured logger, consumed by ai-hwaccel, bote, kavach, abaco, …) stores its syscall numbers in `var` slots for arch-dispatch since v2.2.2 (`src/syscalls.cyr`: `var _SK_SYS_WRITE = 1;`), and every I/O call is `syscall(_SK_SYS_WRITE, fd, …)` / `syscall(_SK_SYS_CLOCK_GETTIME, …)` / `syscall(_SK_SYS_NANOSLEEP, …)`. **Every one of these is a var-number call, so none reroute on PE → all sakshi output (stderr, file, UDP) is silently dropped on Windows.** ai-hwaccel's 2.3.9 structured logging works on Linux/macOS and is invisible on Windows for this reason. (The DXGI precise-VRAM half of 2.3.9 is unaffected — it uses literal `syscall(0xF012, …)` and works; verified GPU-green on cass.)

## Reproduction

`cycc_win`, `CYRIUS_TARGET_WIN=1` (auto-defined), run on a real Windows x86_64 host:

```cyrius
var w = 1;
var fd2 = 2;
syscall(1, 2,   "T1_lit_lit\n",    11);   # writes
syscall(1, fd2, "T2_lit_varfd\n",  13);   # writes
syscall(w, 2,   "T3_varnum_lit\n", 14);   # SILENT — no bytes, no fault
syscall(w, fd2, "T4_varnum_varfd\n",16);  # SILENT
```

```
$ cycc_win < repro.cyr > repro.exe       # 2 warnings, only for the w-number sites
# on cass:
$ repro.exe 2>err.txt ; type err.txt
T1_lit_lit
T2_lit_varfd
```

`T3`/`T4` never appear; exit code 0.

## Root cause

`src/frontend/parse_expr.cyr`, syscall lowering (~line 449+). The number is captured only when the first arg constant-folds:

```
var sc_num = 0 - 1;
...
if (argc == 0) { if (_cfo == 1) { sc_num = _cfv; } }   # only set for a literal/const-fold
...
if (_TARGET_PE == 1) {
    if (sc_num == 1) { if (argc == 4) { EWRITE_PE(S); ... return 0; } }   # never taken for a var
    if (sc_num == 0) { ... EREAD_PE(S); ... }
    if (sc_num == 60){ ... EEXIT(S);  ... }
    ...
}
# falls through to the generic ESCPOPS path → emits `0F 05` (Linux syscall) → non-functional on PE
```

When `_cfo != 1` (non-constant first arg), `sc_num` stays `-1`, no PE case matches, and the generic Linux-`syscall` path is emitted under `_TARGET_PE`. That path is correct on Linux (real `syscall` instruction) but is exactly what cannot work on Windows.

## Proposed fix

Two options; (1) is the real fix, (2) is a stopgap sakshi can ship independently (tracked sakshi-side):

1. **Runtime dispatch for non-literal syscall numbers under `_TARGET_PE`.** When `sc_num == -1` and `_TARGET_PE == 1`, instead of falling through to `0F 05`, emit a small runtime switch on `rax`: compare against the routed set (0/1/2/3/8/9/60/228/0xF0xx) and branch to the corresponding `E*_PE` sequence (or a shared trampoline). Same set the literal path already supports; just resolved at runtime. This makes the portable `syscall(var, …)` idiom work on PE the way it does on Linux, and unblocks every var-dispatch consumer (sakshi first) with no consumer change.

2. **Diagnose, don't silently miscompile.** At minimum, when a `syscall(<non-literal>, …)` is lowered under `_TARGET_PE`, emit a hard *error* (not the soft generic warning), since the result is guaranteed non-functional on Windows. Silent no-op writes are the trap here. (A consumer can then `#ifdef CYRIUS_TARGET_WIN` a literal-number branch — see sakshi stopgap.)

Note that even with (1), sakshi's clock calibration `syscall(_SK_SYS_NANOSLEEP=35, …)` needs `nanosleep` to be a routed PE syscall (it is **not** today: routed set is `0,1,2,3,8,9,60,83,87,228 + 0xF0xx`). For sakshi's default **stderr** path only `write(1)` + `clock_gettime(228)` are needed (both routed) — so fixing (1)/(2) plus routing `nanosleep` (or letting sakshi skip calibration on PE) gets full default-path logging on Windows.

## Consumer-side workaround (shipped today)

ai-hwaccel 2.3.9 ships with structured logging **enabled on Linux/macOS and effectively off on Windows** (the binary builds and runs; logs are silently dropped). No consumer-side fix is possible without patching vendored stdlib (`lib/sakshi.cyr` is synced from the toolchain and would be overwritten). The sakshi-side stopgap (a `CYRIUS_TARGET_WIN` literal-syscall branch in `src/output.cyr`/`src/clock.cyr`) is tracked in sakshi as a **P1** roadmap item: `sakshi/docs/development/issues/2026-06-09-windows-pe-var-syscall-no-reroute.md`.

## Severity rationale

High, not Critical: it doesn't corrupt data or crash shipping binaries (the DXGI literal-syscall path on the same target is fine), but it is a **silent, diagnostic-free total loss of a feature on a tier-1 target**, it bites the portable/correct arch-dispatch idiom (the thing v2.2.2 did *to fix* a different silent-UB bug), and a real consumer is shipping around it right now. The silent-no-op write is the dangerous part — option (2) alone (turn it into an error) would remove the trap.

## Related issues

- `archived/2026-06-08-windows-com-callee-corrupts-caller-in-nontrivial-program.md` — the *other* half of ai-hwaccel 2.3.9 Windows work (DXGI `.rdata` corruption), resolved in 6.1.7. This issue is the logging half.
- sakshi blockers: `sakshi/docs/development/issues/2026-04-30-cyrius-lang-blockers.md` (this is a new row).

## Pointers

- Repro + probes built with `cycc_win` 6.1.15, run on `cass` (Windows 10.0.26200, Intel UHD 600 host).
- cyrius reroute: `src/frontend/parse_expr.cyr` ~449 (`sc_num` fold) and ~547+ (`_TARGET_PE` block); `EWRITE_PE`/`EREAD_PE`/`EEXIT` in `src/backend/x86/emit.cyr`.
- sakshi victim sites: `src/syscalls.cyr` (var defs), `src/output.cyr:27` `_sk_write_stderr`, `:60` `_sk_write_file`, `:272` UDP sendto; `src/clock.cyr` nanosleep/clock_gettime.
- ai-hwaccel consumer: `src/log.cyr`, roadmap 2.3.9.
