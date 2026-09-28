# cycc_aarch64 never prints the `#deprecated` call-site warning

**Status:** ✅ **RESOLVED v6.6.9** (bite 2) — one top-level directive dispatcher (`_tl_directive`) for all seven forks and PARSE_PROG; every fork now arms #deprecated/#must_use/#pure/#io/#alloc before the first statement; gated by `directive_fork_parity.sh` axis 2c.
**Placement:** **6.6.9 bite 2** — One top-level attribute dispatcher for all 7 forks; undefined-prepass parity; aarch64 refuses undefined tail calls (ftype 4); the large-static-data warning on every backend. Pinned 2026-09-27 in [roadmap.md](../../roadmap.md) *The 6.6.7 → 6.6.9 batch* (releases ship strictly in order).
**Discovered:** 2026-09-22, while verifying agnodrm's `#deprecated` adoption on every target.
**Severity:** Low — no wrong code; the build and the binary are correct. But a consumer whose only
lane is aarch64 never learns that an API it calls is going away.
**Affects:** cycc_aarch64 6.6.0, 6.6.2, 6.6.4, 6.6.6.

## Summary

`#deprecated("msg")` on a fn makes every call site print
`warning:<file>:<line>:<col>: '<fn>' is deprecated: <msg>` on x86_64 and agnos, but the same source
built with `--aarch64` prints nothing. This holds for ordinary calls as well as tail calls, so it is
not the v6.6.4 tail-call gap.

## Reproduction

```cyr
include "lib/syscalls.cyr"
#deprecated("use new_thing")
fn old_thing(a): i64 { return a + 1; }
fn main(): i64 { var x = old_thing(2); return x; }
var r = main();
sys_exit(r);
```

| cycc | `cyrius build` (x86_64) | `cyrius build --aarch64` |
|---|---|---|
| 6.6.0 | 1 `is deprecated` line | 0 |
| 6.6.2 | 1 | 0 |
| 6.6.4 | 1 | 0 |
| 6.6.6 | 1 | 0 |

Both builds exit 0 and both binaries behave correctly.

## Root cause (speculation — flagged)

`_DEPRECATED_WARN` (`src/frontend/parse_fn.cyr` ~2351) returns early unless `GFLG(S, fi) & 4`. The
`#deprecated` attribute sets that bit when it transfers onto `fn_flags` (~5154). Because the frontend
is shared, the aarch64 fork presumably either never sets the bit or reads `fn_flags` / `fn_deprecated_msg`
from a different heap band. Unverified.

## Proposed fix

Make the aarch64 fork honour the flag, and extend the existing decoder / `#deprecated` gate
(`tests/gates/frontend/string_token_decoders.sh` axis 2) with an `--aarch64` build of the repro above.

## Consumer-side workaround

Build for x86_64 as well; agnodrm does so on every lane. Its gates deliberately ignore deprecation
lines, so no gate depends on the warning's presence.
