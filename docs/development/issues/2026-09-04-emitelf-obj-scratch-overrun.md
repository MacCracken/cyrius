# `EMITELF_OBJ` overruns its 1 MB scratch — `object;` units above ~31,398 fns SIGSEGV

**Status:** 🔴 **OPEN.** Reproduced on cycc 6.5.49.
**Found by:** the 2026-09-04 roadmap re-triage, while measuring compile-time scaling.
**Severity:** Medium — a hard crash with no diagnostic, plus a silent-corruption band below it.

## Reproduction

```
object;
fn f0(): i64 { return 0; }   … 31,501 of these
fn main(): i64 { return 42; }
```

`build/cycc < that` → **rc=139 (SIGSEGV), zero bytes out, empty stderr.** The same file with
6,001 fns compiles clean (587,520 B). Bisected threshold: 31,397 OK, 31,398 crashes.

## Cause

`EMITELF_OBJ` (`src/backend/x86/fixup.cyr:1706`) carves four sub-regions out of a **fixed 1 MB**
brk block at hardcoded offsets, and its own comment says they are "sized for the v4.7.1 **4096
fn** cap":

```
+0x00000  strtab        (256 KB)
+0x40000  fn_strtab_off (32 KB  — 4096 × 8)
+0x48000  symtab        (100 KB — (4096+5) × 24)
+0x60000  rela          (~400 KB)
```

None is bounds-checked. The symtab zero-loop runs past the block at exactly
`0x48000 + (fnc+5)*24 > 0x100000`, i.e. **fnc ≥ 31,398**.

⚠ **There is a SILENT band below the crash.** At ~12,000 fns with long names, `strtab` (also
sized for 4096) overruns into `fn_strtab_off`: the `.o` is produced with **rc=0** and
`readelf -sW` reports `<corrupt>` symbol names. Bad output, no error. 6,000 fns is clean.

## ⛔ It is REACHABLE, and this repo previously recorded that it was not

`src/backend/x86/fixup.cyr:2136` calls it when `kernel_mode == 3`, which `src/main.cyr:1477` and
`src/main_win.cyr:651` set for an `object;` unit.

v6.5.45's audit recorded the opposite — *"EMITELF_OBJ, which has no callers anywhere in the
tree"* — and used that to classify a `brk` warning in it as benign. **That claim came from a grep
that missed the mode-gated call site.** A negative grep is not proof of unreachability. Both the
audit document and the gate description that repeated it are corrected as of 6.5.49.

## Fix

Size the four sub-regions from the live `fcnt` / fixup count instead of the 4096-fn constants,
and `brk` the computed total. The offsets are currently hardcoded at ~90 call sites within the
function, so they must become computed locals threaded through it.

⚠ **Not a heap-map change** — this scratch is a `brk` extension, not a mapped region, so no
two-step bootstrap is needed. It is deferred from 6.5.49 only because that release's scope was
set by the maintainer and this is a distinct refactor with its own verification bar: object-file
output for small units must stay **byte-identical**, which is a differential test against a
pre-change compiler, exactly as the v6.5.48 ESYSXLAT consolidation was proven.
