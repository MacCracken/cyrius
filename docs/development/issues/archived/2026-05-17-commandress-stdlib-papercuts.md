# commandress stdlib + tooling papercuts

**Filed:** 2026-05-17 during commandress v0.1.0 → v0.2.0 session (M1 cwd/exit/render + CYML config loader)
**Updated:** 2026-05-17 during commandress v0.2.0 → v0.3.0 session (M2 VCS-via-`sit` segment) — added items 6, 7, 8.
**Severity:** Low (most items) / Medium (item 2 — 290 KB bss bloat; item 6 — silent stack overflow in `_exec3`).
**Affects:** `tests/<proj>.bcyr` scaffold, `lib/toml.cyr`, `lib/process.cyr`, `programs/cyrius-lsp.cyr`, `large static data` warning gating.

Composite filing — small papercuts hit while bringing up the first non-trivial commandress feature surfaces. Filing as one doc per user direction during the v0.2.0 session ("note the nit pick and any paper cuts into single doc"). Items split out as standalone proposals when the fix is additive (currently item 3 → [`../proposals/2026-05-17-toml-single-bracket-sections.md`](../proposals/2026-05-17-toml-single-bracket-sections.md); item 8 is a candidate).

## Summary table

| # | Item | Severity | Workaround | Fix-class |
|---|---|---|---|---|
| 1 | `cyrius init` ships a bench scaffold calling non-existent `bench(name, fp, n)` | Low | Replace stub with real `bench_new`+`bench_batch_*` API | Scaffold-template fix |
| 2 | `lib/toml.cyr::toml_parse_file` has a 256 KB on-fn-scope buffer that bloats every consumer's binary | Medium | None — consumers using ANY `toml_*` fn inherit the bss (DCE drops the fn but the static lives) | Heap-alloc in stdlib |
| 3 | `lib/toml.cyr` only parses `[[name]]` (array-of-tables); `[name]` silently drops | Low | Spell every section `[[name]]` even when there's only one | **See proposal** |
| 4 | LSP flags transitive-include symbols as undefined when probing a single .cyr file | Low | Live with the false positives | LSP probe should accept transitive resolution |
| 5 | `large static data` warning fires for statics inside DCE-dropped functions | Low | Ignore the warning when DCE-note is also present | DCE-aware warning gate |
| 6 | `lib/process.cyr::_exec3` has `var argv[4]` — 4 *bytes*, stores 5 pointers (40 B) | **Medium** | Inline a clean fork+pipe in consumer code (commandress vcs.cyr does this) | Fix to `var argv[40]` |
| 7 | `lib/process.cyr::exec_capture` (vec-based) doesn't redirect stderr to /dev/null | Low | Inline fork+pipe with explicit stderr dup2 | Add the dup2 to match `run_capture` |
| 8 | No PATH-lookup helper in stdlib — every consumer rolls its own `_find_in_path` | Low | Inline ~30 LoC PATH walker (see commandress vcs.cyr::_find_in_path) | Add `run_p`/`exec_p` variants, or a `which()` helper |

---

## Item 1 — bench scaffold calls non-existent `bench()` 3-arg form

`cyrius init <name>` ships `tests/<name>.bcyr` with:

```cyrius
fn bench_noop() { return 0; }

fn main() {
    alloc_init();
    bench("noop", &bench_noop, 1000000);
    return 0;
}
```

`bench(name, fp, n)` is not in `lib/bench.cyr`. Running the scaffold-as-is:

```
$ cyrius bench tests/commandress.bcyr
warning: undefined function 'bench'
note: 260 unreachable fns (40027 bytes — set CYRIUS_DCE=1 to eliminate, ...)
warning: undefined function 'bench' (call site may be unreachable)
```

The v5.11.56 wording downgrade ("warning: ...may be unreachable") means the failure isn't fatal, but the scaffold runs zero benchmarks and the user gets only a warning to find. New consumers reasonably assume the scaffold compiles and runs; this trains them away from running benches.

**Proposed fix:** rewrite the scaffold to use the real API — `bench_new` + `bench_batch_start/stop` + `bench_report`. Alternatively, add a 3-arg `bench(name, fp, n)` convenience to `lib/bench.cyr` that internally constructs `bench_new` → `bench_run` → `bench_report`. The scaffold fix is cheaper.

**Consumer-side workaround:** commandress's `tests/commandress.bcyr` was rewritten to the `bench_new` + `bench_batch_start/stop` pattern; see [commandress `tests/commandress.bcyr`](https://github.com/MacCracken/commandress/blob/main/tests/commandress.bcyr) for the shape the scaffold should generate.

---

## Item 2 — toml_parse_file's 256 KB stack buffer balloons every consumer's bss

`lib/toml.cyr` line 270-275:

```cyrius
fn toml_parse_file(path): i64 {
    var buf[262144];                            # 256 KB on-fn-scope static
    var n = file_read_all(path, &buf, 262144);
    if (n <= 0) { return vec_new(); }
    return toml_parse(str_new(&buf, n));
}
```

commandress's config loader uses `toml_parse` directly (after `cyml_parse` splits the header) — it never calls `toml_parse_file`. But the fn is in scope from the include, and the 256 KB on-fn-scope buffer lands in `.bss` regardless of reachability. Measured impact on commandress v0.2.0:

```
$ size build/cmdrs
   text     data    bss     dec     hex    filename
  84050     0     289640   373690  5b3ba   build/cmdrs
```

`bss = 289,640` — ~290 KB. The toml buffer alone is 256 KB of that; the rest is `getenv`'s 8 KB, `cwd_render`'s 4 KB, etc. The binary is 4× the size of its actual code surface.

Cyrius's `large static data (289640 bytes) — consider alloc() for buffers >4K` warning fires correctly. The fix is upstream: heap-alloc in `toml_parse_file` itself.

**Proposed fix:** rewrite `toml_parse_file` to `alloc(buf_size)` instead of an on-fn-scope buffer. Optionally surface a `toml_parse_file_streaming` variant that reads in chunks so 256 KB stops being a hardcoded maximum. (`toml_parse_file_r` v5.8.30 already heap-allocs — `toml_parse_file` should mirror it.)

**Consumer-side workaround:** None practical for a consumer that needs *any* toml fn — including `toml_parse` — because just including `lib/toml.cyr` brings in the unused static. Commandress accepted the 290 KB bss for v0.2.0.

---

## Item 3 — `lib/toml.cyr` only parses `[[name]]`, drops `[name]` silently

See [proposal: TOML single-bracket section support](../proposals/2026-05-17-toml-single-bracket-sections.md). Filing as a proposal because the fix is additive — current behavior isn't broken, it's just incomplete relative to the TOML spec.

**Consumer-side workaround in commandress:** the `~/.commandress.cyml` schema uses `[[prompt]]` / `[[segments.cwd]]` / `[[segments.exit]]` even though each section appears at most once. Documented in [`src/config.cyr`](https://github.com/MacCracken/commandress/blob/main/src/config.cyr) and [`docs/examples/commandress.cyml.example`](https://github.com/MacCracken/commandress/blob/main/docs/examples/commandress.cyml.example). Users coming from starship-flavored TOML will trip over this; once the parser supports `[name]`, both schemas read identically and we can switch.

---

## Item 4 — LSP false positives on transitive-include symbols

`programs/cyrius-lsp.cyr::compile_and_capture()` (v5.11.56's wrapper-fork fix) cd's into the project root and runs `cyrius check --with-deps <filepath>` — which correctly resolves [deps.*] declarations. But for the single-file probe pattern (open `src/render.cyr` in isolation), symbols pulled in via the file's own include graph at runtime aren't visible.

Specifically: commandress's `src/render.cyr` is included by `src/main.cyr`, and `main.cyr` is what brings in `lib/toml.cyr` + `lib/cyml.cyr`. When `render.cyr` is opened in the editor:

```
render.cyr:
  ⚠ undefined function 'toml_pair_key'
  ⚠ undefined function 'cyml_parse'
  ⚠ undefined function 'cyml_doc_header'
  ⚠ undefined function 'toml_parse'
  (etc.)
```

These symbols ARE defined — `render.cyr` includes `src/config.cyr`, which uses them; `config.cyr` doesn't include `lib/toml.cyr` itself because the convention is "main.cyr brings in the stdlib." The build is clean (`cyrius build src/main.cyr build/cmdrs` succeeds).

**Proposed fix:** the LSP single-file probe walks the file's include graph but doesn't transitively walk *callers'* graphs. Two options:

1. **Probe at the project entry point (`src/main.cyr`) instead of the open file** — slower (re-checks every file) but matches build semantics exactly. Per-file diagnostics get attributed by line range.
2. **Treat undefined-fn warnings as soft when the file is not the project entry point** — fast, but loses signal for genuine typos in non-entry files.

Option 1 matches the build's actual reachability model and would have caught the v5.11.56 Item 3 wording downgrade more cleanly too.

**Consumer-side workaround:** none — these are LSP-only false positives, build is unaffected.

---

## Item 5 — `large static data` warning fires for unreachable-fn statics

The warning surfaces in commandress builds:

```
$ cyrius build src/main.cyr build/cmdrs
compile src/main.cyr -> build/cmdrs [x86_64] note: 239 unreachable fns (37733 bytes — set CYRIUS_DCE=1 to eliminate, ...)
warning: large static data (289640 bytes) — consider alloc() for buffers >4K
OK
```

The 289 KB includes `lib/toml.cyr::toml_parse_file`'s 256 KB buffer — a fn that the DCE-aware reachability filter (v5.11.59) correctly identifies as unreachable. The warning is upstream of DCE in the build pipeline, so it counts statics before any pass that could drop them.

Mirrors the v5.11.59 undef-fn check reorder: that one moved AFTER DCE so the filter could suppress dead-host refs. The same shape applies here — gate `large static data` on whether the host fn is in the DCE-eliminated set.

**Proposed fix:** move the static-data accounting to AFTER the DCE pass (when running `CYRIUS_DCE=1`), or filter the byte count by `live[]` like the undef-fn filter does. Outside `CYRIUS_DCE=1`, the warning is honest — those bytes ARE in the bss.

**Consumer-side workaround:** ignore the warning when a `note: N unreachable fns` precedes it on the same compile. Item 2's fix (heap-alloc in toml stdlib) makes this moot for commandress specifically.

---

## Item 6 — `_exec3` argv buffer is 4 bytes, stores 5 pointers (40 B)

`lib/process.cyr::_exec3` (the helper backing `run`, `run_capture`, `spawn`):

```cyrius
fn _exec3(cmd, arg1, arg2): i64 {
    var argv[4];                                  # 4 BYTES — not 4 entries
    store64(&argv, cmd);                          # writes 8 B at offset 0
    var ai = 1;
    if (arg1 != 0) { store64(&argv + ai * 8, arg1); ai = ai + 1; }  # offset 8
    if (arg2 != 0) { store64(&argv + ai * 8, arg2); ai = ai + 1; }  # offset 16
    store64(&argv + ai * 8, 0);                                     # offset 24
    var envp[1];                                  # 1 BYTE
    store64(&envp, 0);                            # writes 8 B
    sys_execve(cmd, &argv, &envp);
    sys_exit(127);
}
```

Per CLAUDE.md ("Every buffer declaration is a contract: `var buf[N]` = N **bytes**, not N entries"), `var argv[4]` reserves **4 bytes** of stack. The code then writes up to 4 × 8 = 32 bytes into it plus a NUL terminator. Stack corruption follows silently — whatever's adjacent (likely `envp`, then the saved frame pointer or local i64s) gets clobbered before `sys_execve` reads argv.

The observable effect surfaced in commandress's vcs segment: `run_capture("/bin/echo", "hello", 0, buf, len)` returned **1 byte** (a lone `\n`) instead of the expected 6 bytes (`hello\n`). `echo` was getting empty argv[1] because the second-pointer store landed past the buffer boundary into territory that got read back as 0 or garbage. Same cause for `run_capture("/home/macro/.local/bin/sit", "status", 0, ...)` returning 0 bytes — `sit` got no `status` arg, ran the default `usage` branch, exited 1.

**Reproduction**:

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
include "lib/result.cyr"
include "lib/tagged.cyr"
include "lib/process.cyr"

fn main(): i64 {
    alloc_init();
    var buf[2048];
    var res = run_capture("/bin/echo", "hello", 0, &buf, 2048);
    var n = result_unwrap_or(res, 0);
    fmt_int(n);                                   # prints "1" — should be 6
    syscall(1, 1, "\n", 1);
    syscall(1, 1, &buf, n);                       # prints just "\n"
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
```

Same code with `exec_capture` (vec-based, heap-allocs argv) prints `6\nhello`. Confirms the bug is `_exec3`'s stack-buffer sizing, not the pipe or fork plumbing.

**Proposed fix**: `var argv[40]` (5 × 8 B = 40 B — argv[0..3] + NUL). Similarly `var envp[16]` (envp[0] + NUL = 16 B with alignment).

```cyrius
fn _exec3(cmd, arg1, arg2): i64 {
    var argv[40];                                 # 5 pointers × 8 B
    ...
    var envp[16];                                 # 2 slots × 8 B
    ...
}
```

**Consumer-side workaround**: commandress's `src/segments/vcs.cyr` inlines its own fork+pipe+execve (`_vcs_capture`) that heap-allocates argv via `alloc(24)`, bypassing `_exec3` entirely. ~25 LoC; no stdlib edit required.

---

## Item 7 — vec-based `exec_capture` doesn't redirect stderr

`lib/process.cyr::run_capture` (cstr 2-arg form) correctly dups stderr to /dev/null in the child:

```cyrius
sys_close(read_fd);
sys_dup2(write_fd, 1);
sys_close(write_fd);
var devnull = sys_open("/dev/null", 1, 0);
if (devnull >= 0) { sys_dup2(devnull, 2); sys_close(devnull); }
_exec3(cmd, arg1, arg2);
```

But `exec_capture` (the vec-based variant added at v5.10.44) only redirects stdout:

```cyrius
if (pid == 0) {
    sys_close(rfd);
    sys_dup2(wfd, 1);
    sys_close(wfd);
    # MISSING: stderr dup2 to /dev/null
    sys_execve(cmd, argv, envp);
    sys_exit(127);
}
```

Effect: commands that print to stderr leak through to the caller's terminal. For commandress's vcs case: `sit: not a sit repository (run 'sit init')` (sit's stderr message when run outside a repo) would surface on every prompt redraw when the user opts in to vcs and is outside a repo. Functionally broken for our case.

**Proposed fix**: copy the dup2 stanza from `run_capture` into `exec_capture` (and `exec_env`, `exec_capture_str`, `exec_env_str` — same gap in all the vec variants). The cstr family does the right thing already; the vec family should match.

**Consumer-side workaround**: same as item 6 — inline the fork+pipe with explicit stderr dup2. commandress's `_vcs_capture` handles both bugs in one wrapper.

---

## Item 8 — no PATH lookup in `lib/process.cyr`

Linux `execve(2)` does NOT do PATH lookup — that's libc's `execvp` family. `lib/process.cyr` wraps bare `execve`, so:

```cyrius
run_capture("sit", "status", 0, buf, len)    # SILENTLY FAILS — child execve→ENOENT
run_capture("/home/macro/.local/bin/sit", "status", 0, buf, len)    # works
```

Every consumer that wants `execvp`-style "find the binary on PATH" semantics ends up rolling the same ~30 LoC walker. commandress's `src/segments/vcs.cyr::_find_in_path` is the third I've seen this session (cyrius-lsp.cyr's `find_cyrius` and `find_cc5` are spiritual cousins).

**Proposed fix** — additive, would normally be a proposal. Filing here for now because it pairs with items 6 + 7 as a coherent `lib/process.cyr` cleanup pass. Two reasonable shapes:

1. **`run_p` / `exec_p` family** — `_p` suffix mirrors the libc convention (`execvp` vs `execve`). One-line consumer migration: `run_capture("sit", ...)` → `run_p_capture("sit", ...)`.
2. **Standalone `which(name)`** — returns the absolute path or 0. Composes with the existing API; consumer does `run_capture(which("sit"), "status", ...)`. Simpler stdlib delta.

Either way, the goal is to stop every Cyrius consumer from inlining the same colon-split-and-access(X_OK) loop.

**Consumer-side workaround**: commandress vcs.cyr's `_find_in_path(name)` — getenv("PATH"), colon-split, access(X_OK)-probe each candidate, return first hit or 0. ~30 LoC.

---

## Cyrius version context

- Cyrius wrapper: `5.11.59`.
- commandress pin (in `cyrius.cyml [package].cyrius`): `5.11.59` (synced via `cyrius lib sync` 2026-05-17).
- Items 1–5 reproduce on the v0.1.0 → v0.2.0 surface; items 6–8 surfaced during v0.2.0 → v0.3.0 (M2 VCS segment via sit).
