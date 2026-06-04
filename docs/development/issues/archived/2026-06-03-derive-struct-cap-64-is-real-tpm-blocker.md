# Per-file `#derive` struct cap (max 64) is the real blocker for libro's `-D LIBRO_TPM` build — corrects the 2026-05-28 type-table issue

**Discovered:** 2026-06-03, re-testing libro's `-D LIBRO_TPM` build under the cyrius 6.0.14 → 6.0.51 toolchain bump
**Status:** ✅ RESOLVED in cyrius 6.0.53 — the cap was raised 64 → **512** as directed. Verified from libro
2026-06-03: standalone repro now builds at 512 derive structs and fails at 513 with `error: too many
#derive structs in one file (max 512)`; libro's `-D LIBRO_TPM` build compiles with `tpm_anchor` as a
plain `#derive(accessors)` struct (the 2.6.5 hand-written-accessor workaround was removed in libro
2.7.1), 502 default / 514 TPM tests pass. The diagnostic-with-count nicety was not bundled (message
still reads `(max 512)` without the observed count) — minor, not reopening for it. Original directive
retained below for the record.

_Original status —_ **RAISE THE CAP (user 2026-06-03), slotted for the next release.** The filer marked
this "no fix required" because the consumer workaround (hand-written accessors) is clean and 6.0.51
now diagnoses the cap loudly. The PROJECT LEADER overrides: the prior issue raised the WRONG cap
(256 type-table → 1024) while declaring libro fixed; the REAL binding limit — the 64-`#derive`-per-file
cap — was never touched. Raise it (heap surgery: relocate + grow the `sizes[]`/`names[]` regions; see
below) so consumers like libro don't need the workaround, and so the misdiagnosis is corrected with
the actual fix rather than a record note.

**Fix scope (heap surgery, bounded — ~.47-class):** the derive regions are tightly packed —
`S+0x197500 sizes[64]` (512 B) + `S+0x197700 names[64*32]` (2048 B) end EXACTLY at `S+0x197F00`,
where include-count / layout-bitfield (`0x197F08`) / pp_depth (`0x197F10`) metadata live. No room to
grow in place. Relocate `sizes[]`+`names[]` to a free heap area (confirm a target in
docs/adr/003-fixed-heap-layout.md), **raise the cap to 512** (user 2026-06-03: generous so it won't
need revisiting — `sizes[512]` = 4 KB + `names[512*32]` = 16 KB = 20 KB contiguous, trivial vs the
~410 KB free gap above the derive region), update every `0x197500`/`0x197700` reference + the `>= 64` check at
lex_pp.cyr:552, and refresh ADR-003 + the layout comments. Verify: the d65/d256 repros build, AND
libro's `-D LIBRO_TPM` builds with `tpm_anchor` as `#derive(accessors)` (no workaround). Bundle the
optional diagnostic nicety here too: `error: too many #derive structs (max N; this unit has M)`.
**Severity:** Informational
**Affects:** `cycc` / `cyrius build` 6.0.51 (cap present at least back through 6.0.14, where it failed silently)
**Corrects:** `archived/2026-05-28-type-table-256-cap-silent-fail.md`
**Reproduction:** inlined below; a scratch copy also lives at `/tmp/2026-06-03-derive-struct-cap-64.cyr` (repros are not committed to this repo).

## TL;DR

The earlier issue blamed libro's TPM-build failure on the **256-entry
type/struct table cap**. That was a **misattribution.** The actual
blocker is a **separate per-file cap: max 64 `#derive` structs per
compilation unit.** 6.0.51 confirms this directly — it now emits:

```
error: too many #derive structs in one file (max 64)
```

The 256-type-table cap is real and was a genuine bug, and 6.0.51 raised
it to 1024 — but it is **not** what gates libro's TPM build, and raising
it unblocks nothing there. The 64-`#derive` cap is the binding
constraint and is unchanged (now diagnosed, no longer silent).

## How the original issue got it wrong

The archived issue reasoned: removing `#derive(accessors)` from
`tpm_anchor` made the TPM build compile, *therefore* the derive's
type-table entries tipped libro over 256 types. The observation
(removing the derive fixes the build) was correct; the **explanation**
(type-table cap) was not. Removing the derive fixes it because it drops
libro under the **64-derive** cap, not the 256-type cap. The two were
conflated because the only lever exercised — deleting one `#derive` —
moves both counters at once. 6.0.51 makes it unambiguous by printing
the exact limit.

## Reproduction (verified on 6.0.51, x86_64 linux)

```sh
# 64 #derive structs -> BUILDS
{ seq 1 64 | awk '{print "#derive(accessors)\nstruct s_"$1" { f0; }"}'; \
  echo 'fn main(){return 0;}'; } > d64.cyr
cyrius build d64.cyr d64.out          # OK

# 65 #derive structs -> FAILS
{ seq 1 65 | awk '{print "#derive(accessors)\nstruct s_"$1" { f0; }"}'; \
  echo 'fn main(){return 0;}'; } > d65.cyr
cyrius build d65.cyr d65.out          # error: too many #derive structs in one file (max 64)

# control: 65 PLAIN structs (no derive) -> BUILDS
{ seq 1 65 | awk '{print "struct p_"$1" { f0; }"}'; \
  echo 'fn main(){return 0;}'; } > p65.cyr
cyrius build p65.cyr p65.out          # OK
```

Boundary is deterministic: 64 derive structs build, 65 fail. The plain-
struct control rules out the type-table cap — 65 plain structs (and far
more) build fine; only `#derive` count is capped at 64.

## How it maps to libro

`-D LIBRO_TPM` pulls in `agnosys` (`lib/agnosys.cyr` — **39 `#derive`
structs**) on top of libro's own modules (**27 `#derive`**, verified by
`grep -c '^#derive' src/*.cyr`). That sum sits just under 64 with
`tpm_anchor`'s accessors hand-written; making `tpm_anchor` a
`#derive(accessors)` struct adds the next one and trips the cap. The
default (non-TPM) build doesn't include agnosys, so it's well clear and
never saw this.

## Status of the two caps in 6.0.51

- **256 type/struct *table* cap** — raised to **1024** (good; the
  257-struct silent FAIL from the archived issue is gone). Not the TPM
  blocker.
- **64 `#derive`-per-file cap** — unchanged; now **diagnosed
  explicitly** instead of failing silently. This is the binding limit.

## Action required: none

The cap is enforced and clearly diagnosed as of 6.0.51; the consumer
workaround is permanent and clean. Filed resolved purely to correct the
historical attribution so nobody re-bisects this expecting the 1024
raise to have fixed it. If a maintainer revisits derive limits for
unrelated reasons, one nicety would be appending the observed count
(`… (max 64; this unit has 65)`). Strictly optional; not requested.

## Consumer-side workaround (unchanged, still correct)

libro keeps `struct tpm_anchor` with **hand-written** `load64`/`store64`
getters+setters instead of `#derive(accessors)`. Accessor *functions*
don't count toward the derive cap — only `#derive` directives do — so
trading the derive for hand-written functions drops back under 64. The
`-D LIBRO_TPM` build compiles clean; 514 TPM / 502 default tests pass on
6.0.51. (Shipped in libro 2.6.5; root cause corrected in libro 2.7.0.)
