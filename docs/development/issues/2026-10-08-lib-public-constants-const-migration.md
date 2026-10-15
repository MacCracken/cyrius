# cyrius's own `lib/` still spells its public constants as `var` — the public-constants-are-`const` migration (asked by the folds' W2 sweeps) — OPEN

**Status:** 🟡 **OPEN** — re-derived 2026-10-08 against 6.7.6 @ 2fb6ad8b: cyrius's non-fold `lib/` declares **0** public
top-level `const`s (its 22 `const`s are all private `_X`) and **325** UPPER_CASE top-level `var X = <literal>;`, of
which **291** are never assigned anywhere in `lib/ src/ cbt/ programs/` (the census below; the roadmap's "302" came
from an unrecorded method — re-derive at the arc's open). The other 34 match a write somewhere: real counters (`AW_*`, `lib/audit_walk.cyr`) and names that are
ALSO enum members in another file (`var O_RDONLY = 0;` in `lib/io.cyr:57` beside the peers' `O_RDONLY = 0;` enum
members; `WS_*` in `lib/ws_server.cyr`) — the second kind is itself part of the collision survey.
Measured: `var X` + `var X` builds; `const X` beside `var X` (either order), `X = …` on a const and `&X` on a const
are each a hard error.
**Placement:** open by design — a feature / arc, not a bug: roadmap_6.md § *The public-constants `const` migration* (placed 2026-10-09) — never 7.x.
**Discovered:** the 6.7.6 fold wave (W2), which left each fold's public-`const` sweep to its own minor and found
sandhi's `HTTP_OK` / `HTTP_NOT_FOUND` blocked by `lib/http.cyr`'s same-name `var`s (roadmap.md § *Constraints on any
fold release*); filed 2026-10-08 from roadmap.md.
**Severity:** Low — no defect today; it gates the folds' own `const` adoption.
**Affects:** cycc 6.7.2 (the release that added `const`) – 6.7.6, `lib/*.cyr` outside the folds.

## Summary

6.7.2 gave cyrius `const` (no storage; every use is the value; an integer folds like an enum constant). cyrius's own
`lib/` has not adopted it: public constants such as the TLS context offsets (`lib/tls_native_ctx.cyr`, 84 of the
291), `lib/regex.cyr` (24), the agnos syscall peer (18), `lib/tls_native.cyr` (18) are still writable globals. The
folds cannot finish their sweeps around that: a fold that declares `const HTTP_OK = 200;` while `lib/http.cyr` has
`var HTTP_OK = 200;` stops compiling ("'HTTP_OK' is already declared as a top-level const"), whichever is converted
first — so the two sides need one sequenced plan and a per-name collision survey across the folds.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
F='sakshi|sigil|bayan|sandhi|ganita|niyama|mabda|vani|yantra|yukti|patra|sankoch'
ls lib/*.cyr | grep -Ev "^lib/($F)\.cyr$" | xargs grep -hE '^(pub )?const [A-Z]' | wc -l          # 0 public (22 private `const _X`)
ls lib/*.cyr | grep -Ev "^lib/($F)\.cyr$" \
  | xargs grep -hE '^var [A-Z][A-Z0-9_]* *(: *[a-z0-9]+)? *= *(0x[0-9A-Fa-f]+|[0-9]+|0 - [0-9]+|"[^"]*") *;' \
  | sed -E 's/^var ([A-Z][A-Z0-9_]*).*/\1/' | sort -u > /tmp/names; wc -l < /tmp/names             # 325
n=0; for v in $(cat /tmp/names); do
  grep -rhE "(^|[^A-Za-z0-9_.])$v *(=[^=]|\+=|-=|\|=|&=)" lib src cbt programs --include='*.cyr' \
    | grep -vE "^ *#|^ *var $v\b" | grep -q . || n=$((n + 1)); done; echo $n                       # 291
printf 'const HTTP_OK = 200;\nvar HTTP_OK = 200;\nsyscall(60, 0);\n' | ./build/cycc > /dev/null      # rc 1
```

(The census is a heuristic: it misses non-literal initialisers and lower-case names, and does not see `&X` uses,
which a `const` also refuses.)

## Root cause

Not a bug — `const` is new (6.7.2) and `lib/` predates it; the conversion was deliberately left as its own arc.

## Proposed fix

The user's arc, because converting a public `var` to `const` makes code that compiles today stop compiling: any
consumer that re-declares the name as a `var` (the sandhi shape), assigns it, or takes `&X`. Shape: (1) a census
committed as a script (names, files, literal value, write / address-of sites in cyrius's tree); (2) a per-name
collision survey against the folds' vendored sources in `lib/` (the folds are the stdlib — consumers are never
surveyed; they meet it at their pin bump via `ecosystem-migration.md`); (3) convert in dependency order with the
fold releases sequenced around it (a fold may only declare `const X` once cyrius's `X` is `const` or gone); (4)
`removed_symbol_census.sh` / api-surface accounting, CHANGELOG + `ecosystem-migration.md` entries, vidya. Names
that are both a `var` and an enum member (the `O_*` family) and genuinely written globals are a separate decision per
name.

## Census addition: the 14 public bound vars (`var X = _X;`) — added 2026-10-15

The census regex above takes literal initialisers only, so it misses the 14 public bounds that 6.7.6 split into a
`const _X` (which sizes the storage) and a public `var X = _X;` (derived with
`grep -nE '^var [A-Z][A-Z0-9_]* *(: *[a-z0-9]+)? *= *_[A-Z][A-Z0-9_]*;' lib/*.cyr`, the folds excluded):

| name | file | const value |
|---|---|---|
| `KEV_SIZE` | lib/async_macos.cyr | 32 |
| `SPAWN_ARGV_MAX` | lib/syscalls_x86_64_agnos.cyr | 1024 |
| `SPAWN_ENV_MAX` | lib/syscalls_x86_64_agnos.cyr | 1024 |
| `TLOCAL_MAX_SLOTS` | lib/thread_local.cyr | 128 |
| `TLS_REG_MAX` | lib/thread_local.cyr (aarch64) | 64 |
| `TLS_RECORD_MAX_PLAINTEXT` | lib/tls_native.cyr | 16384 |
| `TLS_AEAD_NONCE_LEN` | lib/tls_native.cyr | 12 |
| `TLS12_VERIFY_DATA_LEN` | lib/tls_native_hs12.cyr | 12 |
| `TLS12_RANDOM_LEN` | lib/tls_native_hs12.cyr | 32 |
| `TLS_RANDOM_LEN` | lib/tls_native_hs13.cyr | 32 |
| `TLS_HKDF_LABEL_BUF_LEN` | lib/tls_native_keysched.cyr | 514 |
| `TLS_MAX_DIGEST_LEN` | lib/tls_native_keysched.cyr | 48 |
| `TLS_HANDSHAKE_HEADER_LEN` | lib/tls_native_lowlevel.cyr | 4 |
| `TLS_SHA384_CTX_LEN` | lib/tls_native_lowlevel.cyr | 208 |

The user's decision D16 (2026-10-15, issues/2026-10-11-tls-public-bound-vars-api-decision.md): until this arc they stay
writable vars, each commented as a read-only mirror of its `_X`, and since 6.7.12 nothing in lib/ reads any of them
(`lib_buffers_sized_by_const.sh` axis 6 holds all 14), so a write is inert. The arc converts them with the rest: `const
X = <value>;`, the `_X` twin dropped or kept as an alias, and the same accounting (a consumer that assigns one, takes
`&X` or declares its own `var X` stops compiling at its pin bump).
