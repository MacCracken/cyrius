# On Windows, `cyrius build --agnos` and `--target=x86_64-bare-metal-elf` write a plain PE and exit 0 — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) under wine (a
private `WINEPREFIX` / `HOME` / `XDG_CACHE_HOME`, torn down after): `cyrius.exe` and `cycc.exe` built from the tree
(`cc_win` from `src/main_win.cyr`, then `cbt/cyrius.cyr` and `src/main_win.cyr` through it, as
`scripts/build-windows-tarball.sh` does). `cyrius.exe build hello.cyr plain.out`, `build --agnos hello.cyr agnos.out`
and `build --target=x86_64-bare-metal-elf hello.cyr bm.out` all exit 0 and print `compile hello.cyr -> … [x86_64] OK
(2560 bytes)`; the three outputs are byte-identical PE images (`MZ`, md5 bc387dfa…). The bare-metal build also prints
`kernel: entry 0x1000a8, load base 0x100000 (x86_64 ELF64 multiboot2)` — describing an ELF that was not written. Not
re-run on cass (the code path is the PE arm of `compile()`, read below).
**Placement:** 6.7.12 — repair 2, the CLI lane (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-10 — never
7.x (the fix is the user's call, asked at that release's open: a command that "succeeds" today fails by name).
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bite C2-8b (making cbt's Windows compile arm pass the compiler
flags; the target selectors were left out of that list on purpose and nothing refuses them).
**Severity:** High — a wrong artifact with exit 0: a PE where an agnos or bare-metal ELF was asked for, and a
"kernel: entry …" report for an image that does not exist.
**Affects:** the Windows build of the `cyrius` CLI — every version with `--agnos` (v6.0.49) / the bare-metal
`--target` (v6.2.27) and a Windows arm (v6.0.85); measured on 6.7.8

## Summary

`cyrius build` selects a non-default emit target by handing the compiler child environment entries:
`CYRIUS_TARGET_AGNOS=1` for `--agnos`, `CYRIUS_KERNEL=1` + `CYRIUS_ELF64_KERNEL=1` (and `CYRIUS_KERNEL_BASE`) for
`--target=x86_64-bare-metal-elf`. On a POSIX host `_cc_child_inject` pushes those after the compiler flags. The
Windows arm of `compile()` hands cycc.exe only the FLAGS (`_cc_flag_inject`: bounds, dce, strict-pin, poison, pie —
6.7.8 made it the same list as POSIX) and never the target selectors. And passing them through would not help:
the PE-hosted compiler (`src/main_win.cyr`) reads `CYRIUS_TARGET_EFI` but not `CYRIUS_TARGET_AGNOS`,
`CYRIUS_KERNEL` or `CYRIUS_ELF64_KERNEL` — it emits PE (or EFI) only. So the parsed flags are silently dropped and a
PE comes out.

(`--aarch64` on the same host fails loudly — "compiler not found: …\bin/cycc_aarch64" — which is at least not a
wrong artifact.)

## Reproduction

```sh
# from the repo root, on Linux with wine (or on cass with the shipped cyrius.exe / cycc.exe)
W=$(mktemp -d); WP="$W/wine"; mkdir -p "$W/bin" "$W/proj" "$W/h/.cache" "$W/ch"
cat src/main.cyr | build/cycc > "$W/cc" && chmod +x "$W/cc"
"$W/cc" < src/main_win.cyr > "$W/cc_win" && chmod +x "$W/cc_win"
"$W/cc_win" < cbt/cyrius.cyr > "$W/bin/cyrius.exe"; "$W/cc_win" < src/main_win.cyr > "$W/bin/cycc.exe"
printf 'fn main(): i64 { return 7; }\nvar r = main();\nsyscall(60, r);\n' > "$W/proj/hello.cyr"
export WINEPREFIX="$WP" HOME="$W/h" XDG_CACHE_HOME="$W/h/.cache" WINEDEBUG=-all
CH=$(winepath -w "$W/ch")
( cd "$W/proj" && CYRIUS_HOME="$CH" wine "$W/bin/cyrius.exe" build --agnos hello.cyr agnos.out; echo "rc=$?" )
( cd "$W/proj" && CYRIUS_HOME="$CH" wine "$W/bin/cyrius.exe" build --target=x86_64-bare-metal-elf hello.cyr bm.out; echo "rc=$?" )
head -c 2 "$W/proj/agnos.out"; head -c 2 "$W/proj/bm.out"; echo     # MZMZ
WINEPREFIX="$WP" wineserver -k; rm -rf "/tmp/.wine-$(id -u)/server-$(stat -c %D "$WP")-$(printf %x "$(stat -c %i "$WP")")" "$W"
```

```
actual:   both rc=0, "OK (2560 bytes)", both outputs start `MZ` (a PE, identical to a plain build);
          the bare-metal one also prints "kernel: entry 0x1000a8, load base 0x100000 (x86_64 ELF64 multiboot2)"
expected: each refused by name on a Windows host, rc 1 — e.g. "error: --agnos is not available from the Windows
          CLI: cycc.exe emits PE only (build agnos / bare-metal images on Linux)" — or, if a cross compiler is
          shipped for it, an actual ELF
```

## Root cause

- `compile()` (`cbt/build.cyr`): the `#ifdef CYRIUS_TARGET_WIN` arm (`:1630`) builds its environment with
  `_cc_flag_inject(winj)` (`:1294`) only; `_cc_child_inject` (`:1265`), which adds `CYRIUS_TARGET_AGNOS` /
  `CYRIUS_KERNEL` / `CYRIUS_ELF64_KERNEL` / the section base, is the POSIX arm's alone (its comment says so).
- `_cli_apply_target` (`cbt/cli_args.cyr:722`) sets `_agnos_target` / `_baremetal_target` on every host; nothing on
  the PE build refuses them.
- `cbt/commands.cyr:211` prints the "kernel: entry …" line from `_baremetal_target` after any successful compile.
- `src/main_win.cyr` reads none of the three target variables.

## Proposed fix

In the CLI's Windows build, refuse `--agnos` and both bare-metal `--target` values by name before compiling (in
`_cli_apply_target` under `#ifdef CYRIUS_TARGET_WIN`, or at the top of the Windows arm), naming why and where to build
them; check `--win` stays accepted (a no-op there) and `--target=cx` / `js` keep their own arms. Rows (wine, then
cass): `--agnos`, `--target=x86_64-bare-metal-elf`, `--target=aarch64-bare-metal-elf` each rc 1 with the named
error and no output file; a plain build unchanged. ⚠ Unverified, by reading only: the macOS CLI takes the POSIX arm
and DOES pass the selectors, but `src/main_x86_macho.cyr` and `src/main_aarch64_macho.cyr` read none of
`CYRIUS_TARGET_AGNOS` / `CYRIUS_KERNEL` / `CYRIUS_ELF64_KERNEL` either — measure `--agnos` on ecb and ach at the
same slot and refuse it there too if it writes a Mach-O.

## Consumer-side workaround

Build agnos and bare-metal images on Linux (or WSL).
