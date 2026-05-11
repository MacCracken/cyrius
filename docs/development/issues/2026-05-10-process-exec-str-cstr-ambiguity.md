# Issue: `exec_vec` / `exec_env` / `exec_capture` silently break on `Str` args (cstr-only API undocumented)

**Discovered:** 2026-05-10 during argonaut v1.5.2 health-check
resolver work; the audit-deferral comment in
`argonaut/tests/tcyr/audit_findings.tcyr:201` flags this as the
blocker that gates unit-level shell-exec testing for the
`audit-l3-fork-setsid` and `health_exec.tcyr` groups.
**Component:** `cyrius` stdlib — `lib/process.cyr` `exec_vec` /
`exec_env` / `exec_capture` (`exec_cmd` is fine; it `str_data`s
on the way in)
**Severity:** Medium (silent exec failure with `127 / -1` return
codes; no compile-time or runtime diagnostic that the caller is
holding the API wrong)
**Toolchain:** cyrius `5.7.x` through `5.10.40` (current local
build); the stdlib file is byte-identical between the version
argonaut pins (5.10.34) and the latest 5.10 release.

## Summary

The `exec_*` family takes a `vec` of "string args" and stores
each element verbatim into the `execve(2)` argv array:

```cyrius
# lib/process.cyr:117-128 (exec_vec; exec_env / exec_capture identical shape)
fn exec_vec(args) {
    var argc = vec_len(args);
    if (argc < 1) { return 0 - 1; }
    var cmd = vec_get(args, 0);
    var argv = alloc((argc + 1) * 8);
    var avi = 0;
    while (avi < argc) {
        store64(argv + avi * 8, vec_get(args, avi));   # ← BUG
        avi = avi + 1;
    }
    store64(argv + argc * 8, 0);
    ...
    sys_execve(cmd, argv, envp);
```

`execve(2)` reads each `argv[i]` as a NUL-terminated `cstr`.
The implementation assumes every vec element is already a
`cstr` (raw byte pointer). But the natural cyrius idiom —
`vec_push(args, str_from("/bin/foo"))` — pushes a **`Str` fat
pointer** (8-byte heap object containing `{data, len}`). When
`execve` dereferences that, it reads the `Str` struct header as
the start of the command path and either:

- Returns `127` if the bytes happen to form a non-existent path
  (the common case — first 8 bytes are a heap pointer →
  garbled path), or
- Returns `-1` after the kernel rejects the path as too long /
  illegal, or
- Crashes the child mid-exec on rarer struct layouts.

The docstring (`lib/process.cyr:112-116`) shows examples using
**cstr literals** (`vec_push(args, "/usr/bin/ls")`), which work.
There is no caller-side warning when a `Str` is pushed instead.

## Reproduction

```cyrius
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/syscalls.cyr"
include "lib/io.cyr"
include "lib/fs.cyr"
include "lib/process.cyr"

fn main() {
    alloc_init();

    # A: cstr literal — works.
    var a1 = vec_new();
    vec_push(a1, "/bin/true");
    print("A cstr literal: rc="); println_int(exec_vec(a1));

    # B: Str fat pointer — execve(2) sees garbage. rc=127 (path
    # not found) or rc=-1 (path too long), depending on layout.
    var a2 = vec_new();
    vec_push(a2, str_from("/bin/true"));
    print("B Str arg: rc=");      println_int(exec_vec(a2));

    # C: explicit str_data extraction — workaround.
    var a3 = vec_new();
    vec_push(a3, str_data(str_from("/bin/true")));
    print("C str_data(Str): rc="); println_int(exec_vec(a3));

    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
```

```
$ cyrius build /tmp/repro.cyr /tmp/repro && /tmp/repro
A cstr literal: rc=0     # /bin/true returned 0 — exec worked
B Str arg: rc=127        # exec failed — child execve() rejected the path
C str_data(Str): rc=0    # workaround OK
```

Expected: B should either succeed (preferred — the function
detects the API mismatch and DTRT) or fail loudly at compile
time. Actual: silent rc=127, indistinguishable from "binary
genuinely missing".

## Root cause

`lib/process.cyr` was written assuming a cstr-only argv vec.
The signature `(args)` is unannotated — there's no way for the
compiler to flag that pushing a `Str` is wrong, and cyrius has
no runtime type tag distinguishing `Str` from raw cstr pointers.

The asymmetry: `exec_cmd(cmdline)` at line 222 does
`vec_push(args, str_data(part))` correctly — it knows to extract
cstr from Str. That same conversion is missing from
`exec_vec` / `exec_env` / `exec_capture`.

Speculation: the original author intended `exec_*` to be
cstr-only (literal-friendly), with `exec_cmd` as the
Str-friendly variant. But every realistic consumer that wants
to compose argv from runtime-built strings (env var lookup,
config file parsing, vec_push in a loop) ends up with Str
elements and runs into the silent failure.

## Proposed fix

Two viable shapes; both are upstream:

**Option 1 — Always `str_data` defensively.** Make the exec_*
family Str-friendly by default. Inside the argv copy loop,
treat each element as a Str and extract its data pointer:

```cyrius
while (avi < argc) {
    var arg = vec_get(args, avi);
    # If `arg` looks like a Str (8-byte struct: ptr, len), pull
    # its data pointer. Heuristic: treat any pointer that lands
    # in heap-allocated range as a Str. cleaner: introduce
    # `coerce_to_cstr(p)` stdlib helper.
    store64(argv + avi * 8, coerce_to_cstr(arg));
    avi = avi + 1;
}
```

Risk: cstr literals don't have an obvious heuristic distinction
from Str pointers. May need an explicit `vec_push_cstr` / `vec_push_str`
split or a tagged-vec variant.

**Option 2 — New `exec_vec_str(args)` family.** Keep the
existing `exec_vec` as cstr-only and document it explicitly in
the docstring; add a parallel `exec_vec_str(args: vec of Str)`
that always `str_data`s on the way in. Consumers building argv
from `str_from(...)` use the new variant; literal-only consumers
stay on the old one.

Either way, please also:

- Document the cstr requirement in the docstring for the
  existing `exec_vec` / `exec_env` / `exec_capture` so the
  next consumer doesn't re-trip on it. Current docstring shows
  cstr literals only, which reads as a stylistic choice rather
  than a contract.
- Consider whether `cyrlint` or the type-check pass could surface
  pushing a known-Str (e.g. `str_from(...)` return) into a vec
  that's then passed to `exec_vec`.

## Consumer-side workaround

In argonaut, callers run `str_data(s)` before vec_push:

```cyrius
fn check_command(cmd_str, timeout_ms) {
    var parts = str_split(cmd_str, str_from(" "));
    var argv = vec_new();
    for (var i = 0; i < vec_len(parts); i = i + 1) {
        vec_push(argv, str_data(vec_get(parts, i)));   # ← extract cstr
    }
    return exec_vec(argv) == 0;
}
```

This works today, but the wart shows up at every exec call
site. Pre-1.5.0 audit doc (`docs/audit/2026-04-26-audit.md`)
flagged it under L3 follow-ups; argonaut deferred end-to-end
fork-exec testing to the 1.6.x QEMU PID-1 harness arc rather
than work around the API at every test site.

## Affected consumers

- **argonaut** `src/health.cyr` `check_command` —
  current call to `exec_vec(argv)` of cstr (str_data-extracted
  inside the function) — works, but undocumented in callers.
- **argonaut** `tests/tcyr/health_exec.tcyr:19-26` — assertions
  weakened to "result is deterministic (0 or 1)" because the
  Str-vs-cstr handling in `exec_vec` made strict expectations
  brittle. Comment in the file: "exec_vec may return non-zero
  if it doesn't find the binary via Str".
- **argonaut** `tests/tcyr/audit_findings.tcyr:201` — explicit
  comment that this quirk blocks end-to-end fork-exec coverage.
