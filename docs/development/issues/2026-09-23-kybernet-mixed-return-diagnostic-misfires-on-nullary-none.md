# The "returns a `: stack` pair on another path but a SINGLE value here" warning fires on a legal `Some(v)` / `None()` function — OPEN

**Status:** 🟡 **OPEN**: reproduced 2026-09-23 with cycc 6.6.6 on x86_64 and aarch64 (the probe below):
the warning fires, and the program's results are correct on both.
**Placement:** unpinned — 6.6.x-line backlog (never 7.x).
**Discovered:** 2026-09-22 during kybernet 1.7.0. kybernet 1.6.20, built with 6.6.2, had shipped with the
warning on its PID-1 signal path, unexplained.
**Severity:** Low: a misleading diagnostic. It suggests a change (`return Err(x);`) that is wrong for an
`Option`.
**Affects:** cycc 6.6.2 (seen in kybernet 1.6.20) through 6.6.6 (reproduced).

## Summary

A function that returns `Some(v)` on one path and `None()` on another is legal. `lib/tagged.cyr:39-42`
(6.6.6) says so directly: "`None()` returns its tag ALONE and is correctly NOT pair-returning. A
function that returns `None()` on one path and `Some(v)` on another IS pair-returning (the flag
propagates through `return`), and on the None path the payload register is simply not read."

The compiler still warns on the `None()` path that the tag is dropped and "the caller reads this error
as its TAG". The code it warns about is correct. The warning cannot tell a nullary constructor, which
has no payload to drop, from a dropped error tag, which is the defect it exists to catch. A warning
that fires on correct code on every build is one nobody reads, which costs the real cases.

## Reproduction

```cyrius
include "lib/string.cyr"
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
include "lib/tagged.cyr"

# Some(v) on one path, the nullary None() on the other.
fn pick(x) {
    if (x > 0) {
        return Some(x * 10);
    }
    return None();
}

fn say(label, v) {
    var b[32];
    var l = fmt_int_buf(v, &b);
    sys_write(1, label, strlen(label));
    sys_write(1, &b, l);
    sys_write(1, "\n", 1);
    return 0;
}

fn main() {
    var t1, v1 = pick(4);
    var t2, v2 = pick(0);
    say("pick(4) is_some=", is_some(t1));
    say("pick(4) payload=", v1);
    say("pick(0) is_some=", is_some(t2));
    return 0;
}
```

cycc 6.6.6, standalone (no manifest):

```
$ cyrius build probe.cyr probe-x86
compile probe.cyr -> probe-x86 [x86_64] warning:<source>:11:5: `pick` returns a `: stack` pair on another path but a SINGLE value here — the tag is dropped, so the caller reads this error as its TAG. Did you mean `return Err(x);`?
OK (51968 bytes)
$ ./probe-x86
pick(4) is_some=1
pick(4) payload=40
pick(0) is_some=0
```

`cyrius build --aarch64` prints the same warning, and the binary under `qemu-aarch64` prints the same
three lines. Line 11 is `return None();`.

## Root cause

Not investigated from the consumer side. Speculation: the check flags any single-register `return` in a
function that pair-returns elsewhere, without asking whether the returned expression is a nullary
variant's constructor.

## Proposed fix

Exempt a `return` whose expression is a nullary variant constructor (`None()`, or a payload-less
variant of any sum type) from the mixed-return check. `tagged.cyr` documents those as correctly not
pair-returning. Keep the warning for every other single-value `return`, since those are the dropped
tags it exists for. If a hint stays, it could name the nullary case, since `return Err(x);` is not a
fix for an `Option`.

## Consumer-side workaround

kybernet 1.7.0 changed `read_signal` (`src/lib/signals.cyr`) from `Some(signum)` / `None()` to
`Ok(signum)` / `Err(errno)`. Both variants carry a payload, so the function pair-returns on every path
and the warning is gone. That worked for kybernet because a failed signalfd read has an errno worth
carrying. A function whose "nothing" really is nothing has no such out.
