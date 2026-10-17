# `regression_pipe_to_bin` kills its CALLER with SIGPIPE (exit 141) when the child exits without reading its stdin — the check driver died mid-run — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane (unit S1): a full `sh scripts/check.sh` on the
lane tree (ede6b7e1) ended "FAILED (exit 141): programs/checks (the cyrius check binary)" right after the
"tls_native ... links into a freestanding kernel ELF" row, i.e. in `_monomorph_substrate_gate`
(programs/checks/platform_efi.cyr), whose `_pipe_file_to_bin(bin, src)` pipes the 847-byte fixture into a binary that
exits 42 without reading stdin. Nothing in this lane touched programs/checks/ or lib/regression.cyr; the fixture
compiles and exits 42 with the lane's compiler. Pre-existing (the helper has no SIGPIPE handling at f133fb2f either).
**Placement:** 6.7.15 — repair 5 (structs lane; filed from the 6.7.14 structs lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — a stdlib helper (lib/regression.cyr, cyrius's own lib) kills the process that calls it; in the
check driver it ends every driver row after it with no verdict (the shell gates still run), and under parallel load
the small-input case is a race, so the check is FLAKY rather than red.
**Kind:** stdlib (lib/regression.cyr) + tooling (programs/checks).

## Repro

Deterministic with an input larger than the pipe buffer (the 847-byte fixture is the same race, lost only when the
child exits before the parent's write):

```cyrius
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/io.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/args.cyr"
include "lib/fnptr.cyr"
include "lib/flags.cyr"
include "lib/syscalls.cyr"
include "lib/assert.cyr"
include "lib/bounds.cyr"
include "lib/tagged.cyr"
include "lib/result.cyr"
include "lib/fs.cyr"
include "lib/process.cyr"
include "lib/audit_walk.cyr"
include "lib/net.cyr"
include "lib/regression.cyr"
var EMPTY[8];
store64(&EMPTY, 0);
var n = 0;
var i = 0;
while (i < 3) {
    var rc = regression_pipe_to_bin("/path/to/e42", "/path/to/big.txt", &EMPTY);
    if (rc == 42) { n = n + 1; }
    i = i + 1;
}
syscall(60, n);
```

with `e42` built from `syscall(60, 42);` and `big.txt` 200,000 bytes:

```
probe exit=141      # want 3: each call returns the child's 42
```

## Root cause

`regression_pipe_to_bin_capture` (lib/regression.cyr) writes the source into the child's stdin with
`regression_pipe_write_all`, which handles a short or failed write (`w <= 0` returns) — but SIGPIPE is never
ignored, so a write to a pipe whose reader has exited delivers SIGPIPE and the CALLER dies before `sys_write` can
return EPIPE.

## Proposed fix

Block or ignore SIGPIPE around the write in the parent (restoring the caller's disposition after), so EPIPE comes back
as a short write and the helper goes on to reap the child and return its status; a row in a gate driving the
helper at a child that never reads (a > 64 KB input, deterministic) and at the monomorph fixture's shape.
