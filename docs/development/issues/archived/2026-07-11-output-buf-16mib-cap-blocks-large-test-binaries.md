# `output_buf` is a fixed 16 MiB region and `_check_output_cap` hardcodes `16777216` — a large single-translation-unit binary (e.g. a full test suite) that legitimately exceeds 16 MiB is rejected with `output too large`, with no growable path — request: raise to 1024 MiB

**Discovered:** 2026-07-11 during thoth 0.30.5 (the T3 GUI file-tree pane cut). thoth's
single-file test program `tests/thoth.tcyr` (the whole driver + all vendored spine
deps + the full unit suite in one translation unit) compiled to **16 781 048 bytes**
and was rejected — **3 832 bytes** over the 16 MiB cap — when a new GUI view-builder
module + its unit tests were added.
**Severity:** Medium — a consumer stopgap exists (keep the added tests lean, or split
the suite into a second `.tcyr`), but the cap structurally limits how large a single
compiled unit can grow and has already forced real code out of the test binary (see
Impact). It is a hard reject, not a warning, and unlike the codebuf it does **not**
grow.
**Affects:** cycc — **present through 6.4.50** (`grep 16777216 src/backend/common/runtime.cyr`).
The `output_buf` region was last resized **2 MB → 16 MB at v6.1.27** ("phylax
binary-cap"); it has not moved since.

## Summary

cycc emits the final binary into a **fixed-size `output_buf` heap region of 16 MiB**,
and `_check_output_cap` rejects any image whose on-disk size exceeds `16777216`. This
is a *different* cap from the ones a consumer can lean on:

- **codebuf** — 3 MB, **grows to 64 MiB** (`src/main_cx.cyr:88`, "Phase 0 (v6.2.0):
  growable codebuf … EB grows + relocates off-heap"); fn-tables + fixup-table likewise
  growable. These are the caps behind the soft `code buffer at N%` warnings — not a wall.
- **output_buf** — **fixed 16 MiB, not growable.** A translation unit whose emitted
  ELF/Mach-O/PE crosses 16 MiB is rejected outright.

For a project that deliberately puts everything in one compiled unit — which the
test driver does by design (`cyrius test <file.tcyr>` compiles one self-contained
program that `include`s the entire codebase + every vendored dependency + the full
assertion suite) — 16 MiB is reachable through *normal growth*, not abuse. Once hit,
there is no flag, env var, or growable fallback: the only consumer options are to
delete/trim code from the unit or fork it into multiple `.tcyr` files.

## Root Cause

The cap is a single hardcoded literal plus a fixed heap region:

- **The check** — `src/backend/common/runtime.cyr:348` (shared by the ELF / Mach-O /
  PE emit backends, all of which call `_check_output_cap`):

  ```
  fn _check_output_cap(S, filesz): i64 {
      if (filesz > 16777216) {
          syscall(SYS_WRITE, 2, "error: output too large (", 25);
          PRNUM(filesz);
          syscall(SYS_WRITE, 2, "/16777216 bytes)", 16);
          ...
  ```

- **The buffer** — a fixed `output_buf [16777216]` entry in cycc's heap map, per
  target:
  - `src/main.cyr:332` — `0x4D9D000 output_buf [16777216]  16MB ELF output — RELOCATED to heap-top from 0x71A000 (2MB→16MB) @ v6.1.27 phylax binary-cap`
  - `src/main_aarch64_native.cyr:53`, `src/main_aarch64_macho.cyr:65`,
    `src/main_x86_macho.cyr`, `src/main_win.cyr:115` — the same 16 MiB region in each
    per-target layout.

`CYRIUS_DCE=1` does **not** help: it NOPs unreachable functions but leaves their bytes
in the image (`... 1003893 bytes NOPed`), so the on-disk size is unchanged.

## Requested fix

**Raise `output_buf` to 1024 MiB (`1073741824`)** — enough headroom that no realistic
single translation unit hits it again, and cheap because the region is lazy-mapped
(only touched pages cost real memory, exactly like the existing `8MB lazy-mapped`
`vsgn_base`). Concretely:

1. `src/backend/common/runtime.cyr` — change the two `16777216` occurrences in
   `_check_output_cap` (the comparison at :348 and the message at :351) to
   `1073741824` / `"…/1073741824 bytes)"`.
2. Enlarge the `output_buf` region `[16777216] → [1073741824]` and shift the
   downstream heap regions / `brk` top accordingly in each per-target heap map
   (`src/main.cyr`, `src/main_aarch64_native.cyr`, `src/main_aarch64_macho.cyr`,
   `src/main_x86_macho.cyr`, `src/main_win.cyr`) — the same coordinated relocation
   done for the 2 MB → 16 MB bump at v6.1.27.

A smaller bump (e.g. 64 MiB, matching the codebuf ceiling) would also unblock thoth
today, but 1024 MiB is requested so this cap stops being a recurring consumer concern
as generated binaries and single-unit test suites keep growing.

## Consumer stopgap (thoth, in place now)

thoth 0.30.5 kept its new GUI file-tree test **lean** (a fuller version with a
command-scan + a golden-PPM dump overflowed by ~4 KB) and relies on the frame
golden-PPM tests to exercise the full render. This is a workaround, not a fix: every
future GUI test (tree keyboard-nav, tool-call cards, feed scrollback, composer
history) competes for the last few KB under the cap.

## Impact

- **thoth** — the test binary is at the cap. The GUI **present shell**
  (`src/gui/gwindow.cyr`, ~28 KB, + `gpresent.cyr`) is *already* excluded from the
  test binary for exactly this reason (kept `main`-only), so the sovereign Wayland
  client is not unit-tested at all. New pure, headless-testable view-builders now hit
  the same wall.
- **Any consumer** that compiles a large single translation unit — a full-codebase
  test driver, a generated/amalgamated build, a data-heavy program (thoth's unit
  carries ~13 MB of static data: vendored archetype + grammar blobs + a bitmap font)
  — will hit a hard reject with no growable path.

## Reproduction

```sh
# A single .tcyr that includes a large codebase + all vendored deps + a full
# assertion suite, compiled as one translation unit:
cyrius test tests/thoth.tcyr
# error: output too large (16781048/16777216 bytes)
#   FAIL: tests/thoth.tcyr (compile error)

# CYRIUS_DCE=1 does not change the on-disk size:
CYRIUS_DCE=1 cyrius test tests/thoth.tcyr
# error: output too large (16781048/16777216 bytes)
```
