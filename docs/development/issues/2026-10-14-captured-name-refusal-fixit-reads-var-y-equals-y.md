# The captured-name refusal's fix-it reads `var y = y;` when the captured name is `y` — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 struct lane's tree (`l6711-struct` @ `d2dd38fa`), x86_64.
The refusal itself is new in 6.7.11 (`85c648c3`, issues/archived/2026-10-08-struct-operator-results.md #6; the lane base said
"undefined variable 'y'"), so this is wording in the lane's own diagnostic, not a regression.
**Placement:** 6.7.13 — repair 3: struct values (closures lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 struct lane's review.
**Severity:** P3 — diagnostic wording only: what compiles and what it computes are unchanged.

## Reproduction

```sh
cat > capy.cyr <<'X'
include "lib/syscalls.cyr"
fn main(): i64 {
    var y = 5;
    var f = |d| { y += d; return y; };
    return callptr(f, 2);
}
syscall(60, main());
X
build/cycc < capy.cyr > capy.bin; echo "rc $?"
```

Actual:

```
error:<source>:4:25: 'y' is captured by value; a captured name is not assignable in a closure — copy it into a local (`var y = y;`)
        var f = |d| { y += d; return y; };
                            ^
rc 1
```

Expected: the refusal (rc 1) unchanged, with a fix-it that is the suggested copy — not `var y = y;`, which names the
local the same as the capture (it shadows it, and reads as a self-initialisation).

## Root cause

`_asg_cap_name` (`src/frontend/parse.cyr`, 6.7.11) always prints the local's name as the literal `y`:
`"... copy it into a local (`var y = "` + `<name>` + `";`)"`. For a capture named `y` the two coincide. Pick a name
derived from the capture (e.g. `var <name>_l = <name>;`) or drop the local's name from the hint. The gate
`tests/gates/diagnostics/closure_capture_name_write_named.sh` matches the message text (`CAP=...(\`var y = x;\`)`) and moves
with it.
