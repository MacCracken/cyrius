# Ecosystem migration note — 6.6.18: a `.deps` sidecar is what the compile-verify proves, nothing more

> **Created 2026-10-06** for cyrius 6.6.18 (P4 option 2, bites distlib-D1…D5 and the review fix
> dde1c170). The sidecar figures below were measured on scratch copies of the 11 distlib folds
> regenerated with the 6.6.18 CLI, not on the folds' committed `dist/`. Re-derive before acting on any
> of them. The folds' own regeneration is cyrius's post-tag wave (sakshi first); everything else here
> is the reader's, at its own pin bump.

## What changed

Before 6.6.18, `cyrius distlib` seeded a fold's `dist/<pkg>.deps` sidecar from three inferences — the
umbrella include scan (v6.2.48), the producer's whole `[deps] stdlib` declaration **unioned** in
(v6.5.10), and a profile prune (v6.4.48) — and the compile-verify fixpoint only ever ADDED to that seed.
Every producer's test-only leaves therefore reached every consumer: 75 published sidecars named
`assert` and 68 of those bundles referenced no assert symbol; 53 named `bench` and 51 used none of it.

From 6.6.18 the compile-verify fixpoint is the ONLY authority. The seed is the `lib/` includes the
bundled modules keep; the fixpoint, compiling the bundle on six targets (x86_64 Linux, Windows, macOS
and agnos, aarch64 Linux and macOS), derives the rest. A sidecar names exactly the leaves the bundle
needs. `[deps] stdlib` still feeds auto-prepend and `cyrius deps` for the package's OWN builds; it no
longer reaches the published sidecar.

Every bundle also gains a compile-verified **requires block** — one `include "lib/<leaf>.cyr"` per
sidecar leaf, under `# Requires (compile-verified; the leaves of dist/<pkg>.deps):` — so
`include "dist/<pkg>.cyr"` alone compiles. A `cyrius deps` consumer is unaffected by the block:
include-once is keyed on the literal path, the same lines it auto-prepends.

## Producers: `distlib --check` reads STALE at the 6.6.18 pin bump

Every pre-6.6.18 bundle with leaves is stale under 6.6.18, and `--check` names the cause:

    the committed bundle predates cyrius 6.6.18's requires block — run cyrius distlib --all

Run `cyrius distlib --all` and commit the regenerated `dist/`. Expect the sidecar to SHRINK (see the
table) and, for a producer that calls a stdlib family it never declared, to name it. Two more things
the 6.6.18 verify does that a producer may notice:

- **agnos is a verify target.** A non-symbol failure on agnos ALONE is a named warning, not a
  refusal — the other five targets stay authoritative — so a producer never built for agnos is not
  refused.
- **Names nothing owns are reported.** At convergence each name still undefined is printed with the
  targets it fails on (`warn: distlib: dist/x.cyr uses N name(s) still undefined after the sidecar
  verify converged …`). A warning; the exit status is unchanged. A bundle that deliberately calls a
  consumer-supplied hook will list the hook.

## Consumers: declare every stdlib leaf you need — including what your folds need — until 6.6.19

A consumer that compiled only because some producer's sidecar OVER-reported a leaf — vendoring it
into the consumer's `lib/` as a side effect — loses that leaf when that producer regenerates. Until
cyrius 6.6.19 re-vendors the folds with their requires blocks, **any leaf your build needs must be in
your own `[deps] stdlib`: what your code calls, AND what a stdlib fold you declare calls.** The
vendored folds include nothing themselves (`lib/sandhi.cyr` needs sakshi; `lib/ws_server.cyr` needs
bayan and sandhi).

The same applies to `assert` and `bench`: no producer's sidecar carries them any more, so a consumer
that uses them declares them.

**Worked case — takumi.** takumi declares `stdlib = [..., "sandhi", ...]` but not `sakshi`. sandhi's
fold calls `sakshi_span_enter` / `sakshi_span_exit`, and the only thing that ever put
`lib/sakshi.cyr` in takumi's `lib/` was sigil's old sidecar. Once sigil regenerates, takumi's build
fails:

    warning: undefined function 'sakshi_span_enter'
    error: refusing to emit binary with 2 reachable undefined function(s)
    hint: 'sakshi_span_enter' is defined by stdlib leaf 'sakshi' — add it to [deps] stdlib in cyrius.cyml

The last line is new in 6.6.18: on a failed compile the CLI looks each undefined name up in the
stdlib snapshot and names the leaf that defines it (silent for leaves already in scope, for unknown
names and on success; `cyrius fuzz`'s COMPILE FAIL prints the same). **Add the leaf the hint names,
run `cyrius deps`, rebuild** — and repeat while a `hint:` line names another. Keeping the leaf after
6.6.19 is harmless.

## Families expand from the producer's snapshot

A stdlib family directory (`lib/unicode/`) is now ONE sidecar entry owned by the family name — the
spelling producers declare and `cyrius deps` expands — and the requires block expands it into its
member includes from the PRODUCER's stdlib snapshot. A consumer pinned to a cyrius whose snapshot
lacks one of those members meets a named `cannot open include file` on that member. Bump the pin to
at least the producer's.

## Per-fold sidecar leaves, before → after

Measured on scratch copies, 6.6.18 CLI. "before" is the committed sidecar; "—" in the before column is
a profile that had none. Every run converged within 3 recording rounds (mabda), against the 6-round
cap. niyama keeps `unicode` (now derived, not unioned); mabda gains `io` through the agnos target.
yukti 18 → 3 because its named deps (sakshi, patra) bring the rest. One name stays reported:
`sys_recvmsg` on x86_64-windows, from mabda's named dep samvada, which has no Windows wrapper (filed
with samvada). sakshi is not in the table: it has no distlib-generated sidecar yet — its first is part
of the wave.

| sidecar | before (committed) | after (6.6.18) | dropped | added |
|---|---|---|---|---|
| bayan-base64 | 3 | 2 | str  | — |
| bayan-bigint | 3 | 2 | str  | — |
| bayan-csv | 4 | 3 | str  | — |
| bayan-cyml | 6 | 6 | — | — |
| bayan-json | 10 | 10 | — | — |
| bayan-pdf | 7 | 7 | — | — |
| bayan-toml | 6 | 6 | — | — |
| bayan-u128 | 1 | 1 | — | — |
| bayan-yaml | 10 | 10 | — | — |
| bayan | 13 | 10 | assert bench tagged  | — |
| ganita | 10 | 3 | assert bench io str string syscalls vec  | — |
| mabda | 18 | 12 | args dynlib sankoch str tagged thread thread_local  | result  |
| niyama | 9 | 4 | assert fmt io syscalls vec  | — |
| patra | 14 | 14 | — | — |
| sandhi-discovery | 14 | 15 | — | result  |
| sandhi-rpc | 14 | 15 | — | result  |
| sandhi-server | 13 | 14 | http  | result thread_local  |
| sandhi-tls | 10 | 11 | — | result  |
| sandhi | 28 | 18 | args assert atomic dynlib fdlopen fs http mmap process regression tagged ws  | result thread_local  |
| sankoch-brotli | — | 2 | — | — |
| sankoch-bzip2 | 3 | 2 | syscalls  | — |
| sankoch-core | 1 | 0 | alloc  | — |
| sankoch-gzip | 4 | 2 | assert vec  | — |
| sankoch-tar | 5 | 3 | assert vec  | — |
| sankoch-woff | — | 2 | — | — |
| sankoch-xz | 3 | 2 | syscalls  | — |
| sankoch-zip | 5 | 3 | assert vec  | — |
| sankoch-zipall | 5 | 3 | assert vec  | — |
| sankoch-zlib | 4 | 2 | assert vec  | — |
| sankoch-zstd | 3 | 2 | syscalls  | — |
| sankoch | 8 | 7 | assert  | — |
| sigil-aes | 9 | 5 | alloc io str syscalls  | — |
| sigil-argon2 | 8 | 4 | alloc io str syscalls  | — |
| sigil-authenticode | 12 | 12 | alloc syscalls  | fmt result  |
| sigil-chacha | 9 | 5 | alloc io str syscalls  | — |
| sigil-ecdsa | 9 | 10 | alloc syscalls  | fmt result vec  |
| sigil-ed25519 | 11 | 12 | alloc syscalls  | fmt result vec  |
| sigil-hkdf | 8 | 4 | alloc io str syscalls  | — |
| sigil-hmac | 8 | 4 | alloc io str syscalls  | — |
| sigil-mldsa | 13 | 13 | alloc syscalls  | fmt result  |
| sigil-secureboot | 11 | 10 | alloc  | — |
| sigil-sha | 8 | 4 | alloc io str syscalls  | — |
| sigil-tpm | 14 | 11 | result str sys  | — |
| sigil-x509 | 11 | 12 | alloc syscalls  | fmt result vec  |
| sigil | 26 | 19 | assert bench fnptr fs result sakshi str  | — |
| vani-core | 3 | 3 | — | — |
| vani | 21 | 14 | args atomic fmt fnptr sync tagged thread_local vec  | result  |
| yantra | 28 | 23 | args assert dynlib fdlopen fnptr fs io mmap process tagged vec  | ct freelist keccak random result ws_server  |
| yukti-core | 1 | 0 | alloc  | — |
| yukti | 18 | 3 | alloc args atomic chrono fmt fnptr freelist io str string sync syscalls tagged thread_local vec  | — |

## Sequence

1. cyrius 6.6.18 tags; the installed slot is refreshed at the tag.
2. The 12 folded stdlibs regenerate in ONE wave (sakshi, bayan, sandhi, sigil, then ganita, niyama,
   mabda, vani, yantra, yukti, patra, sankoch) — cyrius's own work, each a patch release.
3. cyrius 6.6.19 re-vendors all 12 from their tags; `lib/log.cyr`, `lib/ws.cyr` and
   `lib/ws_server.cyr` include their folds; the native TLS stack drops its mirror of sigil's leaves.
4. Everyone else meets this at their own pin bump. Nothing here is swept.
