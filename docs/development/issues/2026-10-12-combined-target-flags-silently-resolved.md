# `cyrius build` takes contradictory target flags (`--win --aarch64`, `--win --agnos`, `--aarch64 --target=js`, …), silently keeps one and exits 0 — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 on Linux x86_64 against the 6.7.10 slot-open tree (`efb6623f`,
`build/cycc` 2,057,744 B), with the CLI built from `cbt/cyrius.cyr` by that `build/cycc`, the tree's `cycc_aarch64`
/ `cycc_cx` beside it, and a throwaway `HOME` / `CYRIUS_HOME`. Every pair below exits 0 and prints `OK`:
`--win --aarch64` and `--agnos --aarch64` write the byte-identical plain aarch64 ELF (`--win` / `--agnos` dropped);
`--win --agnos` writes a PE32+ that matches neither a plain `--win` nor a plain `--agnos` build;
`--win --target=x86_64-bare-metal-elf` writes a PE32+ and reports `kernel: entry 0x1000a8 … (x86_64 ELF64
multiboot2)`; `--aarch64 --target=x86_64-bare-metal-elf` writes an AArch64 ELF (entry 0x40000078, byte-identical to
`--target=aarch64-bare-metal-elf`) and reports the x86 kernel line; `--win --target=cx` / `--aarch64 --target=cx`
write the plain `.cyx`; `--aarch64 --target=js t.ts t.js` writes a 65,888-byte AArch64 ELF named `t.js` (mode 0644)
and prints `[js] OK`. Two `--target` values ARE refused (the parser's one-value rule).
**Placement:** 6.7.12 — repair 2, the CLI lane (roadmap.md § *6.7.12*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (its tools findings: `cbt/cli_args.cyr:723-725`); re-verified and
filed by the 6.7.10 planning lane.
**Severity:** Medium — a wrong or unintended artifact with exit 0 and an `OK` (and for the bare-metal pairs a kernel
report describing an image that was not written), on a command line that asks for two targets. The
`--aarch64 --target=js` shape also blocks forever on an interactive terminal: the aarch64 compiler reads its stdin
as the source.
**Affects:** every compiling verb that takes the target block (`_cli_verb_compiles`: build, run, test, bench, fuzz,
check, capacity, soak, smoke, doctest, distlib, publish, package, audit) on every host, since the selectors could
first be combined (`--win` v6.0.52, `--agnos` v6.0.49, `--target` v6.1.12 / v6.2.27, cx); measured on 6.7.10's open.

## Summary

The target selectors are independent switches. `_cli_apply_target` sets `_arch` (`--aarch64`), `_win_target`,
`_agnos_target` and the `--target` flags each on its own, and nothing checks that at most one emit target was asked
for. Each consumer then reads the switch it cares about: `current_cc()` picks `cycc_aarch64` from `_arch`, and
`_cc_child_inject` hands that compiler `CYRIUS_TARGET_WIN=1` / `CYRIUS_TARGET_AGNOS=1`, which the aarch64 fork does
not read; the x86 `cycc` gets both `CYRIUS_TARGET_WIN` and `CYRIUS_TARGET_AGNOS` at once; the cx and js arms ignore
`_arch` / `_win_target`; the kernel report reads `_baremetal_aa`, not the compiler that ran. The source comment above
`_cc_child_inject` already says the targets are "distinct emit targets — do not combine"; nothing enforces it.

The js case is the 6.6.6 bite-23b defect reached by a second road: `_target_cc_has_js` asks whether the HOST's
compiler fork has the TS front end (it does, on x86_64 Linux), but `_emit_js` then execs `current_cc()`, which
`--aarch64` made `cycc_aarch64`. That compiler ignores `--emit-js`, reads stdin, and the result is renamed over the
`.js`.

## Reproduction

```sh
# POSIX sh (word-splits $f); writes only under $W
cd /home/macro/Repos/cyrius
W=$(mktemp -d); mkdir -p "$W/bin" "$W/p" "$W/h" "$W/ch"
build/cycc < cbt/cyrius.cyr > "$W/bin/cyrius" 2>/dev/null && chmod +x "$W/bin/cyrius"
cp build/cycc build/cycc_aarch64 build/cycc_cx "$W/bin/"   # the CLI takes the cycc beside it (v6.5.42)
printf 'fn main(): i64 { return 7; }\nvar r = main();\nsyscall(60, r);\n' > "$W/p/hello.cyr"
printf 'const x: number = 7;\nconsole.log(x);\n' > "$W/p/t.ts"
cd "$W/p"; export HOME="$W/h" CYRIUS_HOME="$W/ch"
for f in "--aarch64" "--win --aarch64" "--agnos --aarch64" "--win" "--win --agnos" \
         "--win --target=x86_64-bare-metal-elf" "--aarch64 --target=x86_64-bare-metal-elf" "--win --target=cx"; do
  o=o_$(echo "$f" | tr -c 'a-z0-9' _)
  "$W/bin/cyrius" build $f hello.cyr "$o" </dev/null > "$o.log" 2>&1
  echo "[$f] rc=$? $(file -b "$o" | cut -c1-34) md5=$(md5sum < "$o" | cut -c1-8) $(grep -o 'kernel:.*' "$o.log")"
done
"$W/bin/cyrius" build --aarch64 --target=js t.ts t.js </dev/null; echo "rc=$? t.js: $(file -b t.js | cut -c1-40)"
cd /; rm -rf "$W"
```

```
actual:
[--aarch64] rc=0 ELF 64-bit LSB executable, ARM aar md5=5b19e65f
[--win --aarch64] rc=0 ELF 64-bit LSB executable, ARM aar md5=5b19e65f
[--agnos --aarch64] rc=0 ELF 64-bit LSB executable, ARM aar md5=5b19e65f
[--win] rc=0 PE32+ executable for MS Windows 6. md5=bc387dfa
[--win --agnos] rc=0 PE32+ executable for MS Windows 6. md5=4c7f7183
[--win --target=x86_64-bare-metal-elf] rc=0 PE32+ executable for MS Windows 6. md5=653be706 kernel: entry 0x1000a8, load base 0x100000 (x86_64 ELF64 multiboot2)
[--aarch64 --target=x86_64-bare-metal-elf] rc=0 ELF 64-bit LSB executable, ARM aar md5=dcb04b05 kernel: entry 0x1000a8, load base 0x100000 (x86_64 ELF64 multiboot2)
[--win --target=cx] rc=0 data md5=dd6ba06b          (== a plain --target=cx build)
emit-js t.ts -> t.js [js] OK
rc=0 t.js: ELF 64-bit LSB executable, ARM aarch64,
expected: every pair refused by name before any compile or dep resolution, rc 1, no output file — e.g.
          "error: --win and --aarch64 select two emit targets; pass one"
```

Without `</dev/null`, `cyrius build --aarch64 --target=js t.ts t.js` on a terminal waits on stdin forever (seen: the
`cycc_aarch64 --emit-js t.ts` child blocked in `read(0)` until killed).

## Root cause

- `cbt/cli_args.cyr:722-745` `_cli_apply_target`: `--aarch64` → `set_arch(ARCH_AARCH64)`, `--win` → `_win_target`,
  `--agnos` → `_agnos_target`, `--target` → `_js_target` / `_cx_target` / `_baremetal_target` (+ `set_arch` for
  `aarch64-bare-metal-elf`), each independently; no exclusivity check.
- `cbt/core.cyr:1096` `current_cc()` chooses the compiler from `_arch` alone.
- `cbt/build.cyr:1264-1276` `_cc_child_inject` pushes `CYRIUS_TARGET_AGNOS=1` and `CYRIUS_TARGET_WIN=1` (both, when
  both are set) to whichever compiler `current_cc()` chose; its comment (`:1261-1262`) says "do not combine".
- `cbt/build.cyr:90` `_emit_js` guards with `_target_cc_has_js()` (`:2366`, the host fork's `_self_host_src()`), then
  execs `current_cc()` (`:91`).
- `cbt/commands.cyr:85` / `:116` dispatch js / cx before and regardless of `_arch` / `_win_target` / `_agnos_target`.
- `cbt/commands.cyr:210-228` prints the kernel line from `_baremetal_aa`, not from the compiler that ran.

## Proposed fix

One exclusivity check at the end of `_cli_apply_target`, before `_auto_deps` (rule 5 of that file): count the emit
targets asked for — `--aarch64`, `--win`, `--agnos`, and `--target=<v>` — and refuse more than one by name
(`--aarch64` with `--target=aarch64-bare-metal-elf` is the one consistent pair; whether to accept it or refuse it as
redundant is a one-line question at the open). In `_emit_js`, check the compiler it will exec, not the host fork
(refuse when `current_cc()` is not the host `cycc`), so the js arm stays closed if a later selector reaches it.
Gate rows (a `tests/gates/toolchain/` script): each pair from the repro rc 1 with the named error and no output file;
each single selector unchanged (byte-identical outputs to today); `--aarch64 --target=js` rc 1 without reading stdin.
Mutation: drop the check → the pair rows go RED. This is the host-independent half of
[the Windows CLI target selectors](2026-10-10-windows-cli-drops-target-selectors.md), which refuses selectors the
PE-hosted CLI cannot honour in the same function; the two can share one bite or sit as adjacent bites in the lane.

## Consumer-side workaround

Pass one target selector per invocation.
