# `cyrius header lib/net.cyr` prints `cyr_val sock_send_a(..)` / `cyr_val sock_recv_a(..)`, rc 0, for two `: i64` fns that return lib/result.cyr's pair — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-15 by the 6.7.13 tools lane (unit T4) while applying D37 (lib/result.cyr's
`ok_via` / `err_via` re-annotated `: Result`; issues/2026-10-15-6712-behaviour-changes-beyond-the-decisions-text.md
item 2). Measured with the lane's build/cyrius and build/cycc (l6713-tools @ d0c220dc).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (tools lane; filed from the 6.7.13 tools lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Low — a generated C header that is silently wrong for two public stdlib fns: a C caller reads the tag
(rax) and never sees the payload (rdx), the defect D23 fixed for a pair the header can see. No memory corruption (a
16-byte register return). The guide documents the limit ("a pair reached through another file's fn or a method is not
seen", cyrius-guide.md, the `cyrius header` paragraph), so the header is behaving as documented; the question is
whether cyrius's own lib should carry fns that hit it.
**Affects:** lib/net.cyr `sock_send_a` / `sock_recv_a` (`fn …(a, fd, buf, len): i64 { … return err_via(..); return
ok_via(..); }`, lib/net.cyr:818 / :825) since 6.6.0 made Result the value form; `cyrius header` since 6.7.12 (D23).

## Reproduction

```sh
build/cyrius header lib/net.cyr | grep _a\(; echo "rc=$?"
```

```
cyr_val sock_send_a(cyr_val a, cyr_val fd, cyr_val buf, cyr_val len);
cyr_val sock_recv_a(cyr_val a, cyr_val fd, cyr_val buf, cyr_val len);
rc=0          (nothing on stderr)
```

cycc's own oracle says the fn returns the pair — `nb.cyr`:

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/io.cyr"
include "lib/net.cyr"
fn main(): i64 { alloc_init(); var x = sock_send_a(0, 1, "hi", 2); return 0; }
var r = main();
syscall(60, r);
```

```
$ build/cycc < nb.cyr > nb; echo rc=$?
error:<source>:6:38: a `: stack` enum returns two values — bind both: `var tag, val = f();`
rc=1
```

expected: either `cyr_val2 sock_send_a(..)` (declared `: Result`, as D37 did for `ok_via` / `err_via`; measured for
those: callers byte-identical) or a refusal by name, rc 1 — never `cyr_val`.

## Root cause

`_hdr_pair_scan` (cbt/quality.cyr) knows the pair fns of the scanned file (and the stdlib's payload constructors `Ok
Err Some Left Right`); `ok_via` / `err_via` live in lib/result.cyr, which lib/net.cyr includes, so `return
ok_via(a, n);` reads as a word call and the `: i64` signature stands. Two fixes, either the user's: re-annotate the two
net.cyr wrappers `: Result` (the D37 shape, a two-line lib edit; prove caller-identical with the corpus differential),
or have the header follow `include`s for pair fns (a wider change that would also re-judge the folds' wrappers that
call another file's pair fn).
