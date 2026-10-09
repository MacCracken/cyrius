# `cyrius distlib` credits a symbol undefined on EVERY target to its first declarer in directory order — a fold monolith wins; check.sh is RED whenever `TMPDIR` is on tmpfs — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b: `tests/gates/toolchain/distlib_sidecar_host_independent.sh`
run 3 of 3 with `TMPDIR` on tmpfs (a scratch dir under `/tmp`, tmpfs on this box), the CLI built from `cbt/cyrius.cyr`
with the tree's `build/cycc` (byte-identical to `build/cyrius`) → `FAIL: … axis 3: [zzz_mono sysz ] — EINTRZ (undefined
on PE only) was credited to a monolith, the first declarer in directory order`. A `-v` run of the axis-3 fixture shows
WHERE: `sidecar verify round 1: zzz_mono recorded for 'EINTRZ' (every target)` — the every-target branch, not
`_distlib_partial_owner`.
**Placement:** 6.7.7 (being fixed in this release) — never 7.x.
**Discovered:** 2026-10-08, after the 6.7.6 release gate (reproduced then on a pristine `git archive` of HEAD; recorded in
`state.md`'s Gates row and roadmap.md's backlog); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — a sidecar whose content depends on the publishing host's directory order (exactly what the gate
exists to stop), and check.sh RED on any host whose `TMPDIR` is tmpfs (workaround: `TMPDIR` on disk).
**Affects:** the `cyrius` CLI through 6.7.6 (the every-target branch has used the first declarer since the 6.6.11 union;
not bisected).

## Summary

The sidecar verify classifies each undefined name by the set of targets that left it undefined. A name undefined on SOME
targets goes through `_distlib_partial_owner` (the 6.6.18 D3 owner rule: fold bundles drop out while a non-fold file
declares the name, then the dispatcher whose peer declares it, then the one non-peer declarer, else a named refusal). A
name undefined on EVERY target goes through `_distlib_leaf_defining`, which returns the FIRST snapshot file declaring it
in `dir_list` order — no fold rule, no dispatcher preference, no ambiguity refusal. Round 1 of the verify compiles the
bundle before any `[deps] stdlib` leaf is in the unit, so a name like the fixture's `EINTRZ` is undefined everywhere in
round 1 and is credited to whichever of `aaa_mono` / `mmm_mono` / `zzz_mono` / `sysz_linux` / `sysz_macos` the directory
lists first. tmpfs lists newest-first, so the last-written monolith (`zzz_mono`) wins every time; on this box's ext4
(hash order) the fixture passes, which is how the 6.7.6 release gate read GREEN.

## Reproduction

```sh
S=<scratch dir on tmpfs>; mkdir -p "$S/t"
cat cbt/cyrius.cyr | build/cycc > "$S/cyrius" && chmod +x "$S/cyrius"
TMPDIR="$S/t" CYRIUS_BIN="$S/cyrius" sh tests/gates/toolchain/distlib_sidecar_host_independent.sh
```

Expected: `PASS` (axis 3: the sidecar is `sysz` alone). Actual, 3 of 3 runs: `FAIL … axis 3: [zzz_mono sysz ]`. The same
fixture with `cyrius distlib -v` prints `round 1: zzz_mono recorded for 'EINTRZ' (every target)` and
`round 1: sysz recorded for 'SYSZ_READ' (every target)`. Fixture directory order on tmpfs: `zzz_mono`, `mmm_mono`,
`aaa_mono`, `sysz_windows`, `sysz_common`, `sysz_pub`, `sysz_macos`, `sysz_linux`, `sysz`.

## Root cause

- `cbt/commands.cyr:4333-4336` — `if (nmask == all_mask) { raw = _distlib_leaf_defining(root, nm); … }`.
- `cbt/commands.cyr:4903-4914` — `_distlib_leaf_defining` walks `_dl_snap_names` (dir_list order, `:4762`) and returns
  the first leaf whose id set holds the name.
- The ranking that would have answered `sysz` (`_distlib_is_fold` `:4150`, `_distlib_drop_folds` `:4170`, the peer /
  dispatcher logic in `_distlib_partial_owner` `:4187`) is only on the partial-mask branch.
- Speculation, not measured on a real fold: the same branch can put a fold monolith (e.g. sigil) into a real consumer's
  sidecar for a name a syscalls peer also declares, depending on the store directory's order on the publishing host.

## Proposed fix

Give the every-target branch the same declarer ranking as the partial one — the declarers mapped to their dispatchers,
fold bundles dropped while a non-fold file declares the name, a single dispatcher / single non-peer declarer wins,
anything else a named refusal — ideally one shared ranking function for both branches (and `_cc_hint_owner` `:4507`,
which already applies the fold drop). Then harden the gate so it cannot pass by hash luck: make axis 3 independent of
`dir_list` order (e.g. run it with the monoliths written both first and last, or pin the order the snapshot is read in)
rather than relying on tmpfs's newest-first listing.
