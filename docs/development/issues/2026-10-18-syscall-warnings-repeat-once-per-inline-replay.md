# A syscall-number warning in an `#inline` fn's body prints once for the definition and again for every call — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 platform lane's tree (l6715-platform, unit P3, after the
fn-local const native-region fix), with the ELF-aarch64 cross compiler built from it (`src/main_aarch64.cyr`).
Filed from the platform lane (met while adding native_region_literal_warns.sh axis 12).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 platform lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — cosmetic: the same `file:line:col` warning is printed N + 1 times for an `#inline` fn called N
times. No program changes behaviour; the diagnostics are correct, only repeated, and a long list of identical lines
hides the other warnings around it.
**Affects:** every warning the aarch64 syscall emitter prints while it emits a call (`_esx_native_warn` — the 6.7.12
native-region renumber warning, literal and constant spelling alike — and the 6.6.x "raw syscall N is x86_64 `X`"
report), because an `#inline` body is emitted once for its own definition and re-parsed (and re-emitted) at every
call site (`PARSE_FNCALL`'s body replay, `STI(S, GFBS(S, fi))` + `_inl_replay_body`).

## Reproduction

`d1.cyr`:

```cyr
#inline
fn inl_c(p): i64 { return syscall(91, p, 0); }
fn g(): i64 { var a = inl_c("/x"); var b = inl_c("/y"); return a + b; }
var x = g();
syscall(60, 0);
```

```sh
cat src/main_aarch64.cyr | build/cycc > cca && chmod +x cca
./cca < d1.cyr > d1.bin
```

```text
warning:<source>:2:44: raw syscall 91 is x86_64 `fchmod`; on ELF-aarch64 that number is `capset`. Use SYS_FCHMOD from lib/syscalls.cyr instead of the raw number.
warning:<source>:2:44: raw syscall 91 is x86_64 `fchmod`; on ELF-aarch64 that number is `capset`. Use SYS_FCHMOD from lib/syscalls.cyr instead of the raw number.
warning:<source>:2:44: raw syscall 91 is x86_64 `fchmod`; on ELF-aarch64 that number is `capset`. Use SYS_FCHMOD from lib/syscalls.cyr instead of the raw number.
```

Three identical lines for one source site (the definition and two calls). The native-region warning does the same:
an `#inline` fn whose body is

```cyr
#inline
fn inl_umount(p): i64 {
#ifdef CYRIUS_ARCH_AARCH64
    return syscall(39, p, 0);
#endif
    return 0;
}
```

called twice prints `warning:inc/inllit.cyr:5:12: raw syscall 39 inside a native-aarch64 region is renumbered → 172
(getpid); write 1039 for native umount2` three times (and, since 6.7.15, the same holds for a local `const NR_IU =
39;` there: tests/gates/platform/native_region_literal_warns.sh axis 12 pins "as often as the literal twin").

## Root cause

The warnings are printed from the emitter at the moment a `syscall(...)` is emitted, keyed on nothing: the replay
re-parses the same body tokens, so the same `syscall` token index reaches the same warning once per emission.

## What a fix needs

One warning per source site: remember the `syscall` token indices already warned (the token index is the same on
every replay of a body) and print each once. If it lands, native_region_literal_warns.sh axis 12's inline row (which
compares the constant's count with its literal twin's) keeps holding, and its message should say "once".
