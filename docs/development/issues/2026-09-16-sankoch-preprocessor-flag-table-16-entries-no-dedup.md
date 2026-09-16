# The preprocessor `#define` table holds 16 entries per compile, shared with every included library, with no de-duplication — OPEN

**Status:** 🟡 **OPEN** — design gap; measured on cycc 6.6.4.
**Placement:** unpinned — 6.x-line backlog (preprocessor).
**Discovered:** 2026-09-16, by sankoch (2.8.0 profile-bundle reset fix).
**Severity:** Low–Medium — a hard build failure, but only once a program's includes together pass
13 user defines; the error message points at `0:1`, not at the define that overflowed.
**Affects:** cycc 6.6.4 (measured); `lex_pp.cyr` flag table.

## Summary

`#define` entries go into one fixed 16-slot table per compile. On x86_64 Linux 3 slots are compiler
predefines, so a PROGRAM — the consumer plus every library it includes — gets 13. Re-defining the
same name takes a new slot each time. Measured: `lib/sigil.cyr` alone uses 7, so sigil plus 7 more
defines anywhere in the program fails. A library therefore cannot use `#define` markers for its own
configuration without risking breaking an unrelated consumer.

## Reproduction

```sh
for n in 13 14; do
  { for i in $(seq 1 $n); do echo "#define FLAG_$i 1"; done
    echo 'fn main() { return 0; }'; echo 'var rc = main();'; echo 'syscall(60, rc);'; } > def$n.cyr
  cycc < def$n.cyr > def$n.bin; echo "defines=$n rc=$?"
done
{ for i in $(seq 1 14); do echo "#define SAME_FLAG 1"; done
  echo 'fn main() { return 0; }'; echo 'var rc = main();'; echo 'syscall(60, rc);'; } > defsame.cyr
cycc < defsame.cyr > defsame.bin; echo "same name x14 rc=$?"
```

```
defines=13 rc=0
defines=14 rc=1   error:0:1: too many preprocessor #define/flag entries (max 16)
same name x14 rc=1   error:0:1: too many preprocessor #define/flag entries (max 16)
```

## Root cause

`src/frontend/lex_pp.cyr` ~2482–2520 (6.6.4): `PP_PREDEFINE` and `PP_DEFINE` both check
`_pp_flag_count >= 16` and append the name hash at `S + 0x190800 + count * 8` (values at
`S + 0x190880`, i.e. the hash array is exactly 16 × 8 bytes before the value array). `PP_DEFINE`
never looks up an existing hash, so a repeated `#define NAME` consumes another slot. There is no
`#undef`.

Suggestions (speculation): de-duplicate in `PP_DEFINE` (update the value in place when the hash
exists); move the table somewhere it can hold a few hundred entries; report the source position of
the overflowing `#define`.

## Why this needs a fix

- **Consumer stopgap in production right now:** sankoch 2.8.0 needed each distlib profile to call
  exactly the reset functions of the modules it bundles. `#define SANKOCH_HAS_<MODULE>` markers with
  `#ifdef`-guarded calls were probed and work in both the include chain and a concatenated bundle —
  but 8–9 markers would break every consumer that also includes sigil. sankoch instead ships a
  hand-maintained `src/reset_<profile>.cyr` dispatcher per profile, enforced by a link gate.
- Libraries can't know what their consumers define, so a 13-slot budget shared across a whole
  program makes `#define` unsafe for any library to use; the non-deduplication means even a
  repeated guard-style define spends the budget.
