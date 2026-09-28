# `defer` does not run when a fn returns a value-form `Result` / `Option` pair — OPEN

**Status:** ✅ **RESOLVED v6.6.7** (bite 2) — a `defer` and every `secret var` zeroise run on every return path; a fn with a defer/secret never tail-calls, and the whole return convention (Ok/Err payload included) is saved around the defer walk. The filed repro prints `3 3 3 3 3 3 3 3` on x86_64, x86_64 `CYRIUS_DCE=1` and aarch64 (qemu). Pinned by `tests/tcyr/crossos/defer_every_return_path.tcyr` and `tests/gates/codegen/defer_every_return_path.sh`. CVE-47.
**Placement:** **6.6.7 bite 2** — defer and secret run on every return path: tail-call divert, whole return-convention save (EDEFER_SAVE/RESTORE), inline exclusion, CVE-46. Pinned 2026-09-27 in [roadmap.md](../roadmap.md) *The 6.6.7 → 6.6.9 batch* (releases ship strictly in order).
**Discovered:** 2026-09-22, during agnodrm's raw-syscall → stdlib-helper sweep. Before/after syscall
traces (native `gdb catch syscall`, `qemu-aarch64 -strace`) showed no `close()` for fds the code
closes in a `defer`.
**Severity:** High — a silent resource leak on every call of every affected fn, with no diagnostic
and no warning. The only workaround is to avoid `defer` entirely in Result-returning fns, which is
the construct's main use case.
**Affects:** cycc 6.6.0, 6.6.2, 6.6.4, 6.6.6 (every 6.6.x tested; x86_64 confirmed by output,
aarch64 by `qemu-aarch64 -strace`).

## Summary

A `defer { ... }` block runs when its fn returns a single value, but is **skipped** when the fn returns
a value-form pair: `return Ok(x);`, `return Err(e);`, or a tail call to another pair-returning fn
(`return other_result_fn(...)`, `return drm_err_io(...)`). Nothing is printed at compile time; the
block simply never executes.

## Reproduction

[`repros/2026-09-22-defer-skipped-on-result-return.cyr`](repros/2026-09-22-defer-skipped-on-result-return.cyr):

```cyr
fn g_pair(p): i64 {                      # returns a Result pair
    var fd = sys_open(p, O_RDONLY, 0);
    if (fd < 0) { return Err(fd); }
    defer { sys_close(fd); }
    return Ok(fd);
}

fn g_plain(p): i64 {                     # returns a single value
    var fd = sys_open(p, O_RDONLY, 0);
    if (fd < 0) { return fd; }
    defer { sys_close(fd); }
    return fd;
}
# main calls g_pair 4x, then g_plain 4x, printing the fd each time
```

```
$ cyrius build repro.cyr out && ./out
3 4 5 6 7 7 7 7          # 6.6.0 / 6.6.2 / 6.6.4 / 6.6.6
```

Expected `3 3 3 3 3 3 3 3`. `g_pair` never closes, so the fds climb 3 → 6; `g_plain` closes every time,
so fd 7 is reused. The same shape leaks a temp file when the deferred statement is an unlink.

## Root cause (speculation — flagged)

A `defer` gets a hidden runtime flag, set when the statement is reached (`src/frontend/parse.cyr` ~2175),
and the epilogue walker runs the flagged blocks (`src/frontend/parse_fn.cyr` ~6260–6300). The
symptom fits the value-form pair return leaving through a path that bypasses that walker —
consistent with the single-value return, which does reach it. Unverified; the Cyrius agent should
confirm which return/tail-call emitter skips the epilogue.

## Proposed fix

Route pair returns (and pair tail calls) through the same deferred-block epilogue as single-value
returns. A gate that runs the repro above per target (x86_64, aarch64 under qemu, agnos) would pin it.
The `rdx` payload must survive the deferred blocks.

## Consumer-side workaround (shipped in agnodrm 1.6.2)

agnodrm had ten `defer`s in nine Result-returning fns, and none of them ever ran. That leaked one
fd or socket per call, and in one fn left an nft temp file behind per call. 1.6.2 removes every
`defer` from `src/` and releases resources explicitly on each exit path, and adds
`test_fd_hygiene`, which asserts the lowest free fd is unchanged after repeated calls; against the
1.6.1 code it fails with `got 37, expected 4`. Other consumers using `defer` for cleanup in a
Result-returning fn are affected the same way. Worth a sweep: `grep -rn "defer {"` in any repo that
has adopted the value form.
