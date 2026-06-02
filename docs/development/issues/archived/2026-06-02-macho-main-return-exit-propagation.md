# 2026-06-02 — macОS Mach-O: `fn main()` return value not propagated to exit code

**Filed:** 2026-06-02 (surfaced during the v6.0.35 `cyrius build` SIGBUS fix)
**Affected stage:** aarch64 Mach-O backend — program entry/exit epilogue
**Severity:** Medium — macOS-built programs that set their exit code via
`return` from `main` exit with the wrong code. Tools are unaffected
(they call `sys_exit` explicitly), and `cyrius build` itself works; this
bites consumer programs built for macOS that rely on the canonical
`fn main()` convention.
**Status:** open. **Target:** v6.0.x platform-cleanup window (before the
AGNOS binary arc).

## Summary

The canonical cyrius entry convention is `fn main()` + an emitted
`var r = main(); syscall(SYS_EXIT, r);` epilogue (see the
gnoboot-efi-main-convention issue). On x86_64 Linux this propagates
`main`'s return value to the process exit code correctly. On the
aarch64 Mach-O target it does **not** — the program exits **1**
regardless of the returned value.

## Reproduction

```sh
printf 'fn main() {\n    return 42;\n}\n' > /tmp/m42.cyr

# x86_64 Linux — correct
cat /tmp/m42.cyr | build/cycc > /tmp/m42 && chmod +x /tmp/m42
/tmp/m42; echo $?            # → 42  ✓

# aarch64 Mach-O (on ecb) — wrong
cat /tmp/m42.cyr | CYRIUS_MACHO_ARM=1 <aarch64-cross-cycc> > /tmp/m42_m
# scp to ecb, codesign -s - -f m42_m, then:
./m42_m; echo $?            # → 1   ✗ (expected 42)
```

Confirmed on real Apple Silicon (`ecb`) with **both** the installed
v6.0.34 `cycc_aarch64` and the v6.0.35 build — so it is **pre-existing,
not a v6.0.35 regression** (the v6.0.35 `&`-shadowing fix is unrelated;
both builds behave identically here).

## Why it went unnoticed

- The macОS tools (cyrfmt / cyrlint / cyrdoc / the `cyrius` wrapper)
  call `syscall(SYS_EXIT, n)` **explicitly**, never relying on the
  `fn main()` return path — so they exit correctly.
- The v6.0.33 macОS self-host smoke used `tiny` (`var x = 42;`, a
  top-level-expression program), not the `fn main()` return shape.
  Whether the top-level-expression exit path also mis-propagates on
  Mach-O is **untested** — verify both shapes when fixing.
- This rhymes with the archived PE exit-propagation issue
  (`2026-05-11-ai-hwaccel-cc5-win-pe-exit-propagation.md`, a different
  target whose `0x40001000` symptom turned out to be a `cmd`
  `%ERRORLEVEL%` test-wrapper artifact — see
  `feedback_windows_errorlevel_test_wrapper`). This one is NOT a
  wrapper artifact: it reproduces with a plain `$?` over ssh.

## Where to look

The Mach-O program entry/exit shim — the `_start`/runtime epilogue that
calls `main` and forwards `x0` into the BSD `exit` syscall. Candidates:

- `src/backend/common/runtime.cyr` `_read_env`/entry plumbing and the
  emitted `var r = main(); syscall(SYS_EXIT, r);` epilogue.
- `src/backend/aarch64/emit.cyr` `ESYSXLAT` / `ESYSCALL` — the BSD exit
  translation (Linux 60 → BSD 1) and whether `main`'s return register
  (`x0`) actually reaches the syscall arg register before `svc #0x80`.
  Note the `_main` stub disassembles to `stp x0,x1; mov x28,sp; b
  <runtime-entry>` — confirm the entry path captures and forwards the
  return value rather than dropping it (exit 1 smells like a default /
  failure-path constant, not garbage).

## Action

Verify both program shapes (`fn main(){return N;}` and `var x = N;`) on
`ecb`, fix the Mach-O entry/exit epilogue so `main`'s return propagates,
and add a real exit-code-propagation assertion to the macОS self-host
gate (not a `var x = 42;`-only smoke).
