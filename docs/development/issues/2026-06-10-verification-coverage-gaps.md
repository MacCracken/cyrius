# Verification coverage gaps (the found-by-consumers class) — VR-01/02/03/04

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../audit/2026-06-10-deep-dive-review.md))
**Severity:** High
**Affects:** tests/fuzz/CI infra 6.1.31. This is the systemic root behind
[`2026-06-04-shipped-broken-functionality-found-by-consumers.md`](2026-06-04-shipped-broken-functionality-found-by-consumers.md).

## VR-01 — full tcyr suite runs on 2 of 5 targets (P1)

The 173-file suite loops only in `ci.yml:185-203` (x86_64 ubuntu) and
`:394-414` (AGNOS container). aarch64 = 26 hardcoded one-liners under qemu
(`:456-482`); the real-ARM `ubuntu-24.04-arm` job runs only self-host + funcgate
(`:533-556`); macos-14 = 5 smokes + self-host + funcgate (`:724-786`);
windows-latest = 24 exit-code minis + self-host + funcgate (`:1223-1262`).
On-hardware tcyr is an opt-in glob, self-described "INTERIM… per-platform test
manifests… is TODO" (`cross-os-selfhost.sh:41-51`). **Zero of 173 tcyr** touch
`fs_win`/`thread_win`/`sync_windows`/`alloc_macos`/`args_macos`/`process_win`/
`syscalls_macos`/`syscalls_windows` — those 8 platform variants are validated
only by funcgate side-effects. Exact "found by ports" class.

**Fix (cheapest first):** copy the `ci.yml:188` per-file loop into the
**aarch64-native** job — it's native POSIX Linux, the suite runs unmodified minus
a ~5-tcyr x86-only SIMD skip-list; zero porting cost, instantly triples
on-real-hardware coverage (v6.1.8 ran the full corpus on pi once, proving it).
Then build the PE-safe/macho-safe manifests the TODO names, promote LIBTEST from
opt-in glob to a standing per-host gate, and add targeted tcyr for the win/macos
stdlib variants.

## VR-02 — fuzzing is vestigial (P1)

`fuzz/` = 5 harnesses (~320 LoC) of fixed-input loops (no PRNG/seed/mutation in
any `.fcyr`) — property tests, not fuzzers. `cyrius fuzz`
(`cbt/commands.cyr:170-224`) is in **no** gate (grep `fuzz` in ci.yml = 0 hits;
the only check.sh gate is auto-prepend parity on a synthetic harness,
`checks/main.cyr:416`). The highest-value hostile-input surfaces are unfuzzed:
cycc's stdin parser (`tests/repro_parser_overflow.cyr` is wired to no gate); the
**network-facing** `lib/tls_native.cyr` record/handshake/DER parsers (5,397 LoC,
default backend, a server parsing network bytes); `x509_parse` (`sigil.cyr:9159+`);
bayan json/toml. All TLS tcyr are positive-path.

**Fix (ascending cost):** (1) wire `cyrius fuzz` into ci.yml + a check.sh gate
(seconds of runtime, kills harness rot); (2) a TLS record/ClientHello mutation
`.fcyr` — truncate/oversize/flip length fields into the record + `_tn_parse`
paths, assert clean error not crash; (3) parser fuzz: mutate the tcyr corpus
bytes into cycc, assert diagnostic-or-success, never signal.

## VR-03 — the 338-input differential corpus is muscle memory, not a gate (P2)

The "logic-preserving" verification used for v6.1.5/.6/.8 (338-input old-vs-new
byte-identical corpus + DCE-torture) exists **nowhere as code** — grep
`corpus`/`differential` across `scripts/*.sh` + `programs/checks/*.cyr` finds
only the TS acceptance gate. It is re-assembled by hand each refactor.

**Fix:** codify as `scripts/differential.sh` — build old cycc (git stash / ref
binary) + new cycc, compile the pinned input set with both, `cmp` all outputs;
include `CYRIUS_DCE=1` torture mode. Land as a manual-trigger gate **before
v6.4.x opens** (the regalloc/copy-prop minor) — it's the only thing standing
between a codegen refactor and a silent miscompile.

## VR-04 — no emitted-binary structural validation (P3)

Across ci.yml + programs/checks/, the only structural assertions on emitted
binaries are `file | grep` magic checks + a single `readelf` symbol-binding check
for `_cyrius_init` (`ci.yml:226`). No ELF program-header / PE import-table /
Mach-O load-command validation. The in-cyrius ELF-symtab parse at `ci.yml:218`
proves the capability exists.

**Fix:** a pure-cyrius binary lint (extend the `:218` ELF parse to PE + Mach-O):
validate headers, section bounds, import tables, entry-in-text; run on every
funcgate-built artifact on all targets, plus a cross-built-vs-native structural
diff.

## Status

Filed 2026-06-10. VR-01 + VR-03 are the highest-leverage process investments to
end the found-by-consumers class; VR-03 specifically gates the v6.4.x refactor minor.
