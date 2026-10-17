# `TLS_SHA256_CTX_LEN` (a literal public var, no const twin) still sizes the transcript clone copy: raising it smashes the stack — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-15 by the 6.7.12 stdlib lane (unit L3) while fixing
[the TLS public bound vars](archived/2026-10-11-tls-public-bound-vars-drive-const-storage.md). That filing covers the seven
`var X = _X;` twins (all read `_X` since 6.7.12); this var is not a twin, so it was outside its surface.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane, wave 2, unit L2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low–Medium (the same class as the twins issue: a program that writes a public stdlib var corrupts its own
stack; no attacker crosses a boundary, so a bug, not a ledger id).
**Affects:** `lib/tls_native_lowlevel.cyr` — `var TLS_SHA256_CTX_LEN = 144;` (:231 on the 6.7.12 stdlib lane tree), read by
`tls_native_transcript_init_in` (the heap ctx, `alloc(TLS_SHA256_CTX_LEN)`) and `tls_native_transcript_digest`
(`memcpy(&clone, hctx, TLS_SHA256_CTX_LEN)` into `var clone[_TLS_SHA384_CTX_LEN]`, 208 bytes on the stack).

## Reproduction

```sh
cat > /tmp/sha256ctx.cyr <<'EOF'
include "lib/tls_native.cyr"
fn main(): i64 {
    alloc_init();
    var t = tls_native_transcript_init(TLS_HASH_SHA256);
    tls_native_transcript_update(t, "abc", 3);
    TLS_SHA256_CTX_LEN = 4096;
    var d = alloc(32);
    var n = tls_native_transcript_digest(t, d);
    sys_write(1, "returned\n", 9);
    return n;
}
syscall(60, main());
EOF
cat /tmp/sha256ctx.cyr | build/cycc > /tmp/s && chmod +x /tmp/s && /tmp/s; echo "exit $?"
# measured on the 6.7.12 stdlib lane tree (x86_64 Linux): exit 139, "returned" never printed
# expected: "returned", exit 32 (the SHA-256 digest length)
```

A LOWERED value is the heap twin of the same defect: `tls_native_transcript_init_in` allocates `TLS_SHA256_CTX_LEN`
bytes and `sha256_init_into` writes sigil's 144-byte ctx into it regardless.

## Root cause

`TLS_SHA256_CTX_LEN` is a public `var` initialised from a literal, and the code that copies sigil's SHA-256 ctx reads
the var, while the clone it copies into is sized by `_TLS_SHA384_CTX_LEN` (const). The 6.7.6 / 6.7.9 / 6.7.12 passes
only covered `var X = _X;` twins; this one never got a twin. A scan of lib/tls_native*.cyr and lib/tls.cyr for a
var-length `memcpy` / `memset` into a stack array (`memcpy(&name, …, UPPER_VAR)`) finds this site only.

## Proposed fix

Give it the twins' shape — `const _TLS_SHA256_CTX_LEN = 144; var TLS_SHA256_CTX_LEN = _TLS_SHA256_CTX_LEN;` with the
two reads going to the const — or read sigil's own ctx size. Either changes what a program that writes the var does
(a crash becomes inert) and adds a 15th name to the public-constants census, which is why it was filed rather than
folded into the twins fix. Row: the repro above prints "returned", exit 32; `lib_buffers_sized_by_const.sh` axis 6
then derives and holds it.
