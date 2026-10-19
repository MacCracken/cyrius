# An `#inline` vector fn's refused call is followed by a refusal Windows does not print — the replay clears the panic latch on x86_64 / aarch64 / cx — RESOLVED

> ✅ **RESOLVED in v6.7.15** (VC-2, `63ec22ff5` — no decision needed: diagnostics only. `_inl_replay_body` saves `_panic` before the replayed body and sets it again after if the caller had set it, so a replay never clears its caller's latch. The filed repro now prints one refusal (10:16) on x86_64, aarch64, cx and PE, as the non-inline control does; x86_64, aarch64 and cx printed a second (11:12). Rows: `tests/gates/codegen/simd_param_inline.sh` axis 5. L1 is the filed repro verbatim: rc 1 and exactly one error on the four targets. L2 is the non-inline control, one error. Mutation (the restore disabled): RED 3. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (V2's base, `build/cycc` 2,416,992 B — the
lane after V1 — and with V2's wrapped-argument bite alike), x86_64 / aarch64 / cx / PE (`CYRIUS_TARGET_WIN=1`).
**Placement:** 6.7.15 — repair 5 (vectors lane, wave 2, unit V1; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — diagnostics only, in a compile that already fails: Windows prints one refusal fewer than the
other targets; no binary is written on any target.
**Affects:** PE vs x86_64 / aarch64 / cx; a latched refusal (ERR_IDENT / ERR_MSG) in a call to an inline candidate
with a vector parameter, followed by another refusal in a later statement.
**Discovered:** 2026-10-17, the vectors lane (V2), comparing PE's refusals with x86_64's for wrapped value-form
arguments.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn mk4(a, b, c, d): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, b); store64(&v + 16, c); store64(&v + 24, d); return v; }
fn lanesn(x: f64v2): i64 { if (load64(&x) == 999) { return 0; } return load64(&x) * 10 + load64(&x + 8); }
#inline
fn li(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn main(): i64 {
    var v: f64v2 = f64v2_make(4, 2);
    var e: f64v4 = mk4(1, 2, 3, 4);
    var r = li(mk4(1,2,3,4));
    r = li(v + 1);
    return r;
}
var rc = main(); syscall(60, rc);
```

```
x86_64 / aarch64 / cx:
error:<source>:10:16: cannot pass 'mk4' to a parameter of a different vector type in a call to 'li'
error:<source>:11:12: a value-form vector argument to 'li' is a local of its type or a call declared to return it (..) - got `v`
PE:
error:<source>:10:16: cannot pass 'mk4' to a parameter of a different vector type in a call to 'li'
```

## Root cause

The first refusal (`ERR_IDENT`) sets the panic latch; `_sar_err` (the second) prints nothing while it is set. On
x86_64 / aarch64 / cx `li` is an inline candidate and its body is replayed at the call (PARSE_STMT on the body's
tokens, whose statement end clears the latch — `_stmt_resync`), so the next statement's refusal prints; Win64 does
not replay a vector-parameter fn (a real call: `_sarg_pe_vform` / `_sarg_vec_call`), so the latch is still set when
the second refusal is reached. Either the replay should not clear a latch its caller set (save / restore `_panic`
around the replay) or the two paths should agree some other way.
