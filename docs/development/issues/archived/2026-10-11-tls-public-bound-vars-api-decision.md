# The public bound vars (`var X = _X;`): stay writable, or become read-only — the TLS stack's first — OPEN (a decision) — RESOLVED

> ✅ **RESOLVED in v6.7.12** (LIB-12, `cc082987`: D16, the user 2026-10-15 — keep them writable vars; a write is inert. Each of the 14 `var X = _X;` declarations in cyrius's own lib/ (the TLS stack's nine, `TLOCAL_MAX_SLOTS`, `TLS_REG_MAX`, `SPAWN_ARGV_MAX`, `SPAWN_ENV_MAX`, `KEV_SIZE`) is documented as a read-only mirror of its `_X`, and since LIB-11 nothing in lib/ reads any of them; the `const` conversion goes with the public-constants arc, whose census (`2026-10-08-lib-public-constants-const-migration.md`) now lists them. Comment-only, binaries byte-identical. Row: `tls_public_bound_writes_inert.tcyr` W — all nine TLS twins written read back (still vars) and a 1.3 ClientHello stays the defaults' 148 bytes (1144 on the 6.7.11 TLS lib). CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN — a decision for the user** (a public-API question). Raised by the 6.7.9 quick lane (bite 5):
[the literal-bounds issue](2026-10-08-lib-literal-bounds-and-writable-public-bounds.md)'s item 5 recorded it as "the
user's call", and that issue is now resolved with the question still open. Verified 2026-10-11 against the merged
6.7.9 tree: outside the TLS stack, every `var X = _X;` twin is read nowhere in `lib/` (gate
`memory/lib_buffers_sized_by_const.sh` axis 6), so writing `TLOCAL_MAX_SLOTS`, `TLS_REG_MAX`, `SPAWN_ARGV_MAX`,
`SPAWN_ENV_MAX` or `KEV_SIZE` compiles and does nothing; the TLS stack's seven still drive storage
([2026-10-11-tls-public-bound-vars-drive-const-storage.md](2026-10-11-tls-public-bound-vars-drive-const-storage.md)).
**Placement:** 6.7.12 — repair 2: the platform release (stdlib lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D16 — keep them writable vars (a write is inert).
fix and [`TLS_CA_MAX_ROOTS`](2026-10-11-tls-ca-max-roots-unread-decision.md)) (the user's call, asked at that
release's open) — placed 2026-10-11 — never 7.x.
**Discovered:** 2026-10-11 during 6.7.9's lib-literal-bounds fix.
**Severity:** Low — no defect once the TLS twins read their consts; the question is what a write should mean.
**Affects:** the 14 public bound vars in cyrius's own `lib/` with a `const _X` twin (6.7.6's split; derived with
`grep -rnE '^var [A-Z][A-Z0-9_]* *(: *[a-z0-9]+)? *= *_[A-Z][A-Z0-9_]*;' lib/*.cyr`, the folds excluded): the TLS
stack's nine — the seven still read (`TLS_HANDSHAKE_HEADER_LEN`, `TLS_MAX_DIGEST_LEN`, `TLS_RANDOM_LEN`,
`TLS_RECORD_MAX_PLAINTEXT`, `TLS12_VERIFY_DATA_LEN`, `TLS12_RANDOM_LEN`, `TLS_SHA384_CTX_LEN`) plus
`TLS_AEAD_NONCE_LEN` and `TLS_HKDF_LABEL_BUF_LEN` — and the five non-TLS twins above.

## Summary

6.7.6 gave each public bound a `const _X` that sizes its storage and kept `var X = _X;` for the API. 6.7.9 made the
const drive every loop and allocation outside TLS, and the TLS stack follows at 6.7.13. After that, a write to any of
these vars is silently ignored — before, it corrupted memory (`thread_local_alloc`'s own comment once advised bumping
`TLOCAL_MAX_SLOTS`). The question is whether the public names should say so at compile time.

## The decision

- **(a) Keep them writable vars (today):** a write compiles and does nothing; each declaration's comment says it is a
  read-only mirror of `_X`.
- **(b) Make them `const`** (`const TLS12_RANDOM_LEN = 32;`, the `_X` twin then redundant): a write, `&X`, or a
  consumer's own `var X` becomes a compile error — the public-constants arc's rule
  ([2026-10-08-lib-public-constants-const-migration.md](../2026-10-08-lib-public-constants-const-migration.md), whose
  census misses these because their initialisers are not literals). A consumer meets it at its pin bump
  (`ecosystem-migration.md`).
- **(c) (b) for the TLS nine now, the non-TLS five with the public-constants arc.**

`TLS_RECORD_MAX_PLAINTEXT` is the one name a program might mean to tune; whether it is a tunable is item 2 of the TLS
twins issue and is asked in the same breath (recommended there: a protocol constant; a real max_fragment_length is a
feature).
