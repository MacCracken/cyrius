# `CYRIUS_DCE=1` segfaults sankhya's benchmark binary — clean without DCE

**Status:** ✅ **FIXED in v6.6.3** — the data-segment vaddr FIXUP patched against is now
frozen for EMITELF_USER, on both the x86 and aarch64 backends. sankhya's bench: rc=139 with
zero output → rc=0 with the full 20-row table, identical to the non-DCE run. Gated by
`tests/gates/codegen/dce_data_vaddr_frozen.sh`, mutation-proven.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-09-11 during the 6.6.2 ecosystem migration sweep (sankhya 3.0.0 → 3.0.1)
**Severity:** High — it is a hard CI gate for the consumer, and DCE is on by default in most
release recipes across the ecosystem.
**Affects:** cycc 6.6.2 (first observed). Not checked against 6.6.0/6.6.1 or against 6.5.72,
where DCE first began actually eliminating.

## Summary

`tests/sankhya.bcyr` built with `CYRIUS_DCE=1` **segfaults immediately** — `rc=139`, zero bytes
of stdout, dying before the first benchmark row is printed. The identical source built **without**
DCE runs to completion and exits 0. DCE is removing something that is still reachable at runtime.

The same repo's **main** binary is built with `CYRIUS_DCE=1` by its CI Build step and is fine, so
this is not "DCE is broken for sankhya" — it is specific to the benchmark translation unit.

## Reproduction

Consumer: `~/Repos/sankhya` at the 6.6.2 migration state (pin `cyrius = "6.6.2"`, deps
varna 2.4.1 / itihas 2.5.0 / avatara 2.14.8).

```sh
cd ~/Repos/sankhya

# clean
cyrius build tests/sankhya.bcyr /tmp/b_nodce
/tmp/b_nodce ; echo "rc=$?"          # rc=0, prints the full benchmark table

# segfault
CYRIUS_DCE=1 cyrius build tests/sankhya.bcyr /tmp/b_dce
/tmp/b_dce ; echo "rc=$?"            # rc=139 (SIGSEGV), NO output at all
```

Observed sizes: `2,660,464` bytes without DCE vs `686,192` with — DCE is removing ~74 % of the
binary, which is a large elimination surface for a bench harness that dispatches every benchmark
body indirectly.

⚠ **Ruled out — this is not the migration edit.** The bench's warm block was changed during the
sweep (`warm = correlate(...)` → a fresh `var _warm_corr_t, _warm_corr_v = correlate(...)`, because
the 6.6.0 value form has no `t, v = f();` reassignment form). Built **both** with and without that
edit, non-DCE, both exit 0; the crash appears only when DCE is enabled, with or without it.

⚠ **Ruled out — the `xalloc` duplicate is NOT the cause.** The CI log for this failure carries

```
warning:lib/avatara.cyr:27:1: duplicate fn 'xalloc' (last definition wins; first defined in lib/itihas.cyr)
```

which looks like a promising culprit: two allocator wrappers, same arity, "last definition wins".
It is genuinely new — `itihas` **2.5.0** introduced `xalloc` (2.4.0 had none) while `avatara` has
carried one since at least 2.9.0 — so the sankhya 3.0.1 dep bump created it. **But it is not the
crash.** Pinning `itihas` back to 2.4.0 removes the duplicate warning entirely (0 occurrences) and
the DCE build **still segfaults with rc=139**. Measured, not reasoned. Do not re-chase this.

(The duplicate is still a real latent collision worth its own fix — both definitions are
allocate-or-abort-on-failure so they are behaviourally interchangeable today, which is exactly why
nothing catches it.)

## Root cause (if known)

**Speculation, not verified.** The bench harness builds its benchmark list as function pointers
(`_b_<name>()` wrappers dispatched via `fncall0`, per the file's own header comment) and hands them
to `bench_run_batch`. That is precisely the shape v6.5.72's closeout called out as the last and
hardest DCE cause: *"ftype-3 fixups (absolute fn addresses behind indirect calls) — invisible to
any body-level audit because every body still decodes."* If a wrapper is reachable **only** via its
address being taken into a table, and the reachability walk does not follow that edge, DCE would
NOP a live body and the first indirect dispatch would jump into eliminated code — which matches the
symptom exactly (immediate SIGSEGV, before any output).

The cyrius agent should verify or correct this; I did not read the DCE reachability walk.

## Impact / consumer stopgap

sankhya's CI runs `CYRIUS_DCE=1 cyrius build tests/sankhya.bcyr` as a required Benchmarks step, so
this blocks its gate. No stopgap has been applied — the bench step is left failing rather than
weakened, because dropping `CYRIUS_DCE=1` there would hide the defect rather than fix it.

## Related

- `docs/development/completed-phases.md` / CHANGELOG v6.5.72 — the ftype-3 fixup class described
  above, which this resembles.

---

## Root cause (v6.6.3) — DCE was not removing anything it should have kept

The filing's reading was "DCE is removing something that is still reachable at runtime".
That is not what happened, and it is worth recording because the whole investigation was
pointed the wrong way by it: **every elimination was correct.** Cross-referencing the 3,354
eliminated fns against the 68 called from the `_b_*` bench bodies gives **zero** overlap,
so the indirect-dispatch hypothesis — the obvious one for a harness that calls through
`fncall0` — is refuted outright.

What broke is the **data segment's address**.

`_wx_data_vaddr` derives the RW segment's vaddr by rounding the END OF CODE up to a 2 MB
boundary, and FIXUP and EMITELF_USER each computed it independently, expected to agree.
`CYRIUS_DCE=1` breaks that ordering:

1. FIXUP computes `dbase` from the current code size;
2. FIXUP bakes every absolute gvar/string address into the code against it (through ~line 305);
3. **the DCE pass then compacts and shrinks `cp`** (line ~332);
4. EMITELF_USER re-derives from the smaller `cp` and emits the PT_LOAD somewhere else.

Measured:

| | no DCE | DCE |
|---|---|---|
| RW `LOAD` vaddr | `0x800000` | **`0x600000`** |
| size | 2,660,464 | 686,192 |
| run | rc=0, 20 rows | **rc=139, zero output** |

`gdb` puts the fault at `movabsq $0x8000b0, %rcx; movq %rax, (%rcx)` — a store into
unmapped space in the run of `0,1,2,3…` writes that is GLOBAL INITIALISATION. It dies
before `main`, which is why there was no output to bisect with.

⭐ **And it explains the detail the filing flagged as puzzling** — that the same repo's
MAIN binary built with DCE is fine. Nothing about the bench is special: its code size just
happens to straddle a 2 MB bucket boundary when compacted, and the main binary's does not.
Any binary would fail given the right size.

### Fix

Freeze the dbase FIXUP patched against and have EMITELF_USER use it. Re-deriving is the
wrong half to keep — the addresses are already in the code by then, so agreeing with them
is the only option that does not require re-patching. The cost is virtual address space
only: the data lands on the pre-DCE 2 MB boundary and the gap is unmapped, exactly as the
W^X design note already describes. `p_vaddr ≡ p_offset (mod 0x1000)` still holds.

Applied to **both** `src/backend/x86/fixup.cyr` and `src/backend/aarch64/fixup.cyr` — the
defect is in the shared shape, not one target's emitter.

### Verification

- sankhya bench with DCE: **rc=139 → rc=0**, RW vaddr back at `0x800000`, and the 20
  benchmark rows are **identical to the non-DCE run**.
- All 7 target forks compile; self-host fixpoint byte-identical; seed-derive OK.

### Noted while here, not a defect

DCE declines to COMPACT when `DECODE_WALK_OK` fails on any body — it still reports the fns
as dead but leaves the bytes NOPed. Measured on synthetic fixtures: 400 dead fns compact
(220,701 bytes eliminated); 4,200 and 22,000 do not. That is the v6.5.72 fail-safe working
as designed, and it is why no in-tree fixture can be grown into the bucket-crossing regime
— which is what forced the gate above to be structural.
