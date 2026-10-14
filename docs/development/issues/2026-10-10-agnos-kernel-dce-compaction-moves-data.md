# agnos — `CYRIUS_DCE=1` cannot shrink a `kernel;` image: compaction miscompiles through 6.6.19 and is declined from 6.6.20 on — OPEN

**Status:** 🟡 **OPEN** — filed by agnos (2026-10-10, agnos 1.57.12). 6.6.20's
REVBE-01 stopped the miscompile by declining compaction on `kernel;`. That also took away the size reduction, and
agnos now needs it.
**Placement:** 6.7.11 — repair 1, the infra lane — agnos-filed, High: the DCE compaction arc's kernel bite (roadmap_6.md) plus the kept-dead-body call retarget (pulled in at the open: user, 2026-10-13) — never 7.x. Was: open by design — a capability gap placed in roadmap_6.md § *The DCE compaction arc* (kernel layouts join it: the miscompile is closed by 6.6.20's decline, what is missing is the shrink) — placed 2026-10-11 — never 7.x. Consumer-reported by agnos with real image-room pressure: the user may promote it into a repair release.
**Discovered:** 2026-10-09/10. The agnos operator ruled to make room with `CYRIUS_DCE=1`, and the DCE kernel died
before its banner.
**Severity:** High. Through 6.6.19 the kernel image is wrong: every string/gvar address points at the pre-compaction place. On agnos it is LOUD, not silent — ~18 serial lines whose strings are all NUL bytes, then death ~0.11 s in, before the banner; a smaller kernel could boot further on garbage.
From 6.6.20 on, a shipping consumer has no way to shrink the image.
**Affects:** cycc 6.5.72 (whole-program compaction) through 6.6.19: miscompile. 6.6.20 and later: correct but no
shrink. x86_64 `kernel;` with `CYRIUS_ELF64_KERNEL=1` (EMITELF64_KERNEL) and ELF32 `kernel;` (EMITELF_KERNEL).
The `CYRIUS_WX=0` userland layout has the same shape.

## Summary

FIXUP patches every absolute gvar and string address against `dbase = entry + acp`, using the PRE-compaction code
size. Then the `CYRIUS_DCE=1` pass compacts `.text`. The kernel emitters put `.bss` at `base + hdr + mb + GCP(S)`,
which is the POST-compaction size, and `.rodata` directly after it. So the data moves down by the number of bytes
eliminated, and every patched address still points at the old place. Only EMITELF_USER reads `_wx_dbase_frozen`.
The stage-1b note in `wp_compact` says "data does not move when code shrinks", which is true only under W^X.

On agnos 1.57.11 with cycc 6.6.6, `CYRIUS_DCE=1` reports 203 dead fns and removes 198 bodies (162,676 B); five dead bodies are kept because each contains an `out` the length decoder cannot size (`outl`, `ahci_hba_reset`, `ramdisk_register_block_dev`, `test_proc_a`, `test_proc_b`) — see the second defect below. The kernel takes control from
gnoboot and prints about 18 serial lines. Every string comes out as the right number of NUL bytes, while
numbers print correctly. Then it dies about 0.11 s in. Nothing matching `AGNOS kernel v` ever appears, so the
smoke classifies it as "died before banner". All 13,966 data-address imm64s in `.text` point
0x27B70 (162,672 B) above the data: the banner literal is referenced at 0x371C23 but loaded at 0x34A0B3.

## Reproduction

The minimal reproduction below was run through the `cyrius build` wrapper at 6.6.6:

```sh
{ echo 'kernel;'
  awk 'BEGIN { for (i = 0; i < 6; i++) printf "fn dead%d(x): i64 { var a = x * %d; var b = a + 7; var c = b * b; return c - a + %d; }\n", i, i + 3, i * 1000 + 7 }'
  printf 'var G = 40;\nvar A[32];\nfn main(): i64 { var s = "kdata"; G = G + load8(s); store64(&A, G); return G; }\nmain();\n'
} > k.cyr
CYRIUS_ELF64_KERNEL=1 CYRIUS_DCE=0 cyrius build --no-deps k.cyr k0.bin   # .bss 0x100448, .rodata 0x100550 — both occur as imm64 in .text
CYRIUS_ELF64_KERNEL=1 CYRIUS_DCE=1 cyrius build --no-deps k.cyr k1.bin   # .bss 0x100160, .rodata 0x100268 — NEITHER occurs; .text still holds 0x100448 / 0x100550
```

Compaction moved the data down by 0x2E8 = 744 B. 744 is 8 mod 16, which matters for the fix below: `A` was
laid out 16-aligned against the old base. The upstream gate `tests/gates/codegen/dce_data_vaddr_frozen.sh` row 7
(added in 6.6.20) is this same check.

## Root cause (cycc 6.6.6 line numbers)

- `src/backend/x86/fixup.cyr:153`: `var dbase = entry + acp;` is computed from the pre-compaction cp, and line 154
  freezes it in `_wx_dbase_frozen`.
- `fixup.cyr:190-192`: arrays larger than 8 bytes are padded to 16 against `va = dbase + totvar`, the old base.
- `fixup.cyr:283-292` (ftype 1, strings) and `:315-324` (ftype 0, gvars) bake `dbase + …` into the code as imm64.
  Under `kernel;` this is the non-PIE absolute branch.
- `fixup.cyr:876-883`: the compaction gate excludes PIE, Mach-O and PE but not `kmode == 1`.
  `src/common/ir.cyr:1638` (`wp_compact`) excludes only `kmode > 1`.
- `ir.cyr:1691-1692` (stage 1b) repairs ftype 2 and 3 and leaves data alone ("data does not move").
- `fixup.cyr:1137-1165` (EMITELF64_KERNEL) has `cp = GCP(S)` with `bss_foff = hdrsz + mb_sz + cp`, so data follows
  the compacted code. `fixup.cyr:957-960` (EMITELF_KERNEL) has the same shape. Only `fixup.cyr:1328`
  (EMITELF_USER) consults `_wx_dbase_frozen`.

## Second defect: a kept dead body's call is retargeted onto an unrelated function

Found by the agnos review of this report. Compaction stage 0 cancels fixups that sit INSIDE removed code, but not a
call FROM a kept body INTO a removed one. agnos's `ramdisk_register_block_dev` is dead but kept (the `out` decoder
refusal above); its call to `blk_register_ramdisk`, which was removed, is shifted by the same arithmetic as every
other call and lands on `blk_read`, an unrelated live function. It is harmless in agnos only because the caller is
itself dead. A gate for the data-address fix (`.bss`/`.rodata` vaddrs present as imm64 in `.text`) would not catch
this: the fix must also either remove/neutralise kept-dead bodies' calls into removed code, or refuse to remove a
callee that a kept body still calls.

## Proposed fix

Make the compaction repair data addresses on layouts where data follows code (`kmode == 1`, and `CYRIUS_WX=0`),
in place of the 6.6.20 decline.

1. After `_wp_sort_prefix` (so `_wp_deleted` is known), choose the new code end `cp' = align8(acp − deleted)`.
   If `(acp − cp') % 16 != 0`, add 8 to `cp'`. That keeps every array at the 16-byte congruence that
   `fixup.cyr:190-192` gave it. In agnos, the TEST+KTEST and ZFS_SELFTEST builds both land on 8 mod 16, and so
   does the repro.
2. Let `data_shift = acp − cp'`. Subtract it from the imm64 at every surviving ftype 0 and ftype 1 fixup site.
   A site survives if its CP is still `>= 0` after stage 0. Like stage 1b, this is plain arithmetic with no
   re-run of the patch loop, so cybs is safe.
3. `SCP(S, cp')`. Any gap bytes are zero, inside `.text`.
4. Static-init slots (`_EMIT_GVAR_STATIC_INITS`) that hold a data address would need the same shift. agnos has
   none: the base differential below found 0 data→data sites. The general fix must either handle them or prove
   that a kernel static init cannot hold an address.
5. Gate: invert `dce_data_vaddr_frozen.sh` row 7. The kernel must now compact, and its `.bss`/`.rodata` vaddrs
   must still occur as imm64 in `.text`. Add a row whose deleted byte count is 8 mod 16, with a `var A[32]` whose
   referenced address must stay 16-aligned.

## Evidence that this fix is sufficient (emulated on agnos, no compiler change)

Each agnos kernel was built three times with the pinned 6.6.6, through `scripts/build.sh`, using a wrapper as
`$CYRIUS_HOME/bin/cyrius`:

- `CYRIUS_DCE=1` at the default base
- `CYRIUS_DCE=1 CYRIUS_KERNEL_BASE=0x200000`
- no DCE

Every 8-byte field that differs by exactly the base delta between the two DCE builds is a patched absolute
address. The plain kernel has 13,981 of them: 13,966 code→data, 15 code→fn (all landing on `55 48 89 e5`
prologues), and 0 unexplained or unclassified. The no-DCE build gives the pre-compaction data window. Re-pointing
the data sites by `data_shift`, with the +8 pad when the shift is 8 mod 16, is exactly what the fix above would
emit. Those images pass:

| build | dead fns / B | data shift | result |
|---|---|---|---|
| plain | 203 / 162,676 | 0x27B70 (≡0) | `agnsh-smoke` **PASS** (all 7 gates). Unrelocated: died before banner. |
| TEST (ktest.sh) | 257 / 199,351 | 0x30AB0 (≡0) | `ktest.sh` **367/370**, the same 3 environmental `[initrd]` checks as the no-DCE run |
| TEST KTEST (ktest.sh) | 252 / 198,062 | 0x305A8 → padded 0x305A0 | serial trace line-identical to the no-DCE build. Both stop after `Syscall write works!`, a pre-existing KTEST+TEST stall that is unrelated to DCE. |
| ZFS_SELFTEST | 200 / 161,693 | 0x27798 → padded 0x27790 | `zfs-smoke.sh` **PASS 7/7** lanes against the OpenZFS-built fixture |

So cycc's reachability analysis is sound for agnos: no live function was removed, and `&fn` handlers (the IDT
and syscall entry) are repaired by stage 1b. The only defect is the data base.

## Consumer-side workaround

None shipped. The base-differential relocation above is exact and fails closed. But it is a post-link binary
rewrite, it triples the compile, and it only works on pins 6.5.72–6.6.19, because 6.6.20 declines compaction.
agnos records it as evidence, not as a mechanism. agnos stays on the non-DCE build until this lands.
