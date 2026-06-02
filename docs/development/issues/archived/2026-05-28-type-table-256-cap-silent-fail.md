# 256-entry type/struct table cap fails silently — the 257th struct/enum makes `cyrius build` print a bare `FAIL`

**Discovered:** 2026-05-28 during libro's cyrius 6.0.1 → 6.0.14 toolchain bump (the `-D LIBRO_TPM` opt-in build)
**Severity:** Medium — hard build failure with no diagnostic; consumer workaround exists (drop `#derive(accessors)` / collapse a type) but it's undiscoverable without bisection
**Affects:** `cycc` / `cyrius build` 6.0.14 (and at least back through the 6.0.x line — libro's TPM build has failed since the 6.0.1 syscalls refactor, which is what nudged its type count over the line)

## Summary

There is a hard cap of **256 type-table entries** (structs + enums +
type aliases) per compilation unit. Defining the **257th** makes the
build fail with nothing but:

```
compile <file>.cyr -> <out> [x86_64] FAIL
```

…and exit 1. No line number, no "type table full", no hint which limit
was hit. The number 256 = 2^8 strongly suggests a `u8` type index (or a
fixed 256-slot table) that overflows/wraps silently instead of erroring.

The silent failure is the worse half of the bug. The cap itself is a
reasonable-ish internal limit; **failing with no diagnostic** turns a
one-line fix ("you have 257 types, max is 256") into a multi-hour
bisection. CYRIUS_STATS doesn't help: on the largest *passing* build it
reports `fn_table 513/8192`, `var_table 0/8192`, `fixup_table
0/262144` — i.e. none of the *printed* tables is anywhere near full, so
the limiting table isn't even surfaced in stats.

## Reproduction

Standalone, no includes (see
`repros/2026-05-28-type-table-256-cap.cyr`):

```sh
# 256 structs -> BUILDS
seq 1 256 | awk '{print "struct s_"$1" { f0; }"}' > t.cyr
echo 'fn main(){return 0;}' >> t.cyr
cyrius build t.cyr t.out          # OK

# 257 structs -> FAILS
seq 1 257 | awk '{print "struct s_"$1" { f0; }"}' > t.cyr
echo 'fn main(){return 0;}' >> t.cyr
cyrius build t.cyr t.out          # compile t.cyr -> t.out [x86_64] FAIL ; exit 1
```

Binary-searched the boundary: **256 builds, 257 fails**, deterministic.
Observed on cyrius 6.0.14, x86_64 linux.

Notes from narrowing it down:
- Plain `struct` and `#derive(accessors) struct` both count toward the
  256 (a derived struct at slot 256 still builds standalone).
- Enums and type aliases share the same table (a file of 256 plain
  structs + 1 more definition of any kind fails).
- It is **not** the fixup table (0/262144 on the passing build), not
  fn_table (513/8192), not var_table (0/8192), and not DCE.

## How it bit libro (the real-world consumer path)

libro's `-D LIBRO_TPM` build pulls in ~235 `struct`/`enum`/`type`
definitions across the stdlib (str, vec, hashmap, json, sigil, patra,
agnosys, …) + its own 21 modules — i.e. it sits right at the 256
boundary. The **default** build is just under and compiles fine; adding
the opt-in `src/tpm_anchor.cyr` (which defines `enum TpmAnchorVerify`
+ `struct tpm_anchor` + `#derive(accessors)`) tips it over 256 and the
whole build dies with the bare `FAIL`.

This is what made it look TPM-specific and compiler-version-specific for
a long time: the 5.10.x → 6.0.1 syscalls refactor added enough stdlib
type definitions to push libro from "just under 256" to "just over with
the TPM module included." Bisecting inside `tpm_anchor.cyr` pointed at
`#derive(accessors)` because removing it drops libro's type count back
under the cap — not because the derive machinery itself is broken.

## Root cause (speculation — flag for maintainer)

A 256-entry (likely `u8`-indexed) type/struct table that the codegen
indexes into, with no bounds check on insert. The 257th `register_type`
(or equivalent) overflows the index / table and a later lookup produces
a malformed reference that aborts codegen, surfacing only as the
top-level `FAIL`. Not verified against cycc internals — the agent that
owns cycc should confirm which table and where the insert is.

## Proposed fix

1. **Diagnostic first (the important half).** On the 257th type, emit a
   real error: `error: <file>: type table full (max 256 types per
   compilation unit)`. Even if the cap stays, this turns the bug from
   "bare FAIL, bisect for hours" into a one-line fix for the consumer.
2. **Widen the table** if cheap — bump the index to `u16` (or make the
   table grow). 256 types per compilation unit is easy to exceed once a
   project includes the full stdlib plus its own modules; libro is a
   mid-size consumer and already hits it.

## Consumer-side workaround (shipped in libro 2.6.5)

Get back under 256 type-table entries. libro replaced
`#derive(accessors)` on `struct tpm_anchor` with four hand-written
getters + four setters using `load64`/`store64` at the struct's field
offsets:

```
struct tpm_anchor { inner; sealed_ctx; pcr_indices; output_dir; }
fn tpm_anchor_inner(ta)       { return load64(ta); }
fn tpm_anchor_sealed_ctx(ta)  { return load64(ta + 8); }
# … + pcr_indices/+16, output_dir/+24, and _set_ store64 variants
```

This dropped libro's type count back under the cap; the `-D LIBRO_TPM`
build compiles clean and all 514 tests pass (502 default). The accessor
*functions* don't count toward the type table — only the type
*definitions* do — so trading the derive for hand-written functions is a
clean escape. Other consumers near the cap can do the same, or collapse
an enum/type alias.
