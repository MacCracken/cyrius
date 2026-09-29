# Cyrius Development Roadmap — v6.6.x (active minor)

**Scope** — the **current active minor only** (v6.6.x). This is the slot-pinning working
artifact: the repair window, the proposal queue, the committed ergonomics list, and the
unscheduled 6.x backlog. Whole-cycle framing plus v6.7.x/v6.8.x live in
[roadmap_6.md](roadmap_6.md); the unpinned watching list is
[roadmap-future.md](roadmap-future.md); per-release history is
[CHANGELOG.md](../../CHANGELOG.md) and [completed-phases.md](completed-phases.md).

> **Reading order**: this file (active-minor slots) → [roadmap_6.md](roadmap_6.md)
> (v6.7.x+ and cycle framing) → [roadmap-future.md](roadmap-future.md) (unpinned / speculative).

> ⚠ **This file was rewritten 2026-09-08 at v6.6.1.** It had been 1,043 lines still titled
> *"v6.5.x (active minor)"* — a closed minor — of which **~480 lines were a slot list where every
> entry read ✅ SHIPPED**. CLAUDE.md's rule is that closed-minor detail lives in the CHANGELOG and
> [completed-phases.md](completed-phases.md) and that this file carries **only what is still
> ahead**; that rule had been violated for a whole minor, which is the same drift the 2026-07-29
> re-scope removed from `roadmap_6.md`. The v6.5.x narrative was not deleted — it is in the
> CHANGELOG per-patch and summarised in `completed-phases.md`'s v6.5.x band. **Do not re-add
> shipped slots here.**

## See also

- [roadmap_6.md](roadmap_6.md) — the **v6.x cycle** beyond this minor: v6.7.x/v6.8.x RISC-V
  rv64, cycle budgeting, and the shape of what follows v6.x.
- [roadmap-future.md](roadmap-future.md) — unpinned / speculative watching list with explicit
  unpin conditions (128-bit div-mod, Phase 3-full varargs, effect tracking, HKTs/GATs).
- [cycle-discipline.md](cycle-discipline.md) — durable operating principles **and the runnable
  closeout checklist + per-closeout ledger**.
- [state.md](state.md) — volatile current state. Refreshed **by hand** every release —
  `version-bump.sh` never touches it (its closing summary names the rows to update).
- [completed-phases.md](completed-phases.md) — historical per-release / per-minor narrative.
  **Closed-minor narrative belongs there, not here.**
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth. When this file and the
  CHANGELOG disagree, the CHANGELOG wins and this file is the bug.

---

## Where we are

**Current head: v6.6.10** (2026-09-29, closed, awaiting the tags) — cycc **1,424,272 B** (`.text` **1,251,248**) ·
seed-derive **GREEN** · cross-OS **GREEN** on ecb/ach/cass/pi · self_compile **833 ms** ·
**394** `.tcyr` (**142** in `crossos/`) · **104** `lib/*.cyr` · **294** shell gates under
`tests/gates/<bucket>/` · **0 open issues** · **6 open proposals**.

> ⚠ **Every figure above was DERIVED on the day, not carried** (re-derived 2026-09-27 at the 6.6.7 open).
> `version-bump.sh` rewrites the version token, replaces the `(…)` after it with the bump date, and
> nothing else — **the numbers beside it are yours to re-derive.** Keep the stamp at the start of its
> line and its parenthetical free of nested `(`/`)`, or the bump refuses to rewrite it (and
> `tests/gates/toolchain/version_bump_doc_anchors.sh` goes red the day it is written). Re-derive gates with `find tests/gates -name '*.sh' | wc -l`; never increment.

**v6.6.0 opened this minor** with its one breaking change: `Result` / `Option` / `Either` are the **value
form** (construction allocates zero bytes), shipped WITH the ecosystem. **v6.6.1–v6.6.6** were the repair
window: 6.6.1 closed the issue queue, 6.6.2/6.6.3 repaired what the ecosystem sweep found, 6.6.4 fixed the
59-release native-aarch64 `cyrius run/test` defect, 6.6.5 the nine issues open at 2026-09-17, and 6.6.6 its
27-bite follow-on (five lanes; see CHANGELOG). **The repair window is CLOSED.** Per-release detail is in the
CHANGELOG; do not re-add shipped slots here.

---

## The 6.6.7 → 6.6.12 batch (planned 2026-09-27; 6.6.10–6.6.12 added by the user 2026-09-28/29; the batch ENDS at 6.6.12)

After the 6.6.6 tag the ecosystem filed **28 new issues** in a week (agnodrm, agnostik, kybernet, daimon,
patra, sigil, kavach, tyche, hisab, samay, sakshi, vani, libro, aethersafha, agnos), on top of the two
6.6.6 left open and the ten-item tail it deliberately did not pack. **The user split that track across three
releases so each batch stays small** (6.6.6 was 27 bites and 193 commits — too big).

Every item was premise-checked against live code at `99a03056` and then adversarially re-verified by a
second, independent agent (15 themed clusters). That pass confirmed all 30 filings still open, and it
also turned up **~40 defects of the SAME classes at sites nobody had filed**: a nested-fn emitter that
drops the enclosing fn's pending returns, `-1.0` evaluating to `-4.0`, an unrouted arm64-macOS syscall that
re-runs a stale `x16`, and lint walkers that score a crashed tool as clean. Under *"an audit's output is
fixes, not a backlog"* those are placed INTO the bite that owns their class, not filed. Six items were
found already shipped or wholly a sibling's (see *Not placed*).

### Rules for these releases

- ⛔ **Releases are strictly sequential.** 6.6.8 does not start until 6.6.7 is tagged, and the same for
  6.6.9. **Parallelism happens only INSIDE a release**: independent bites run in git-worktree **lanes**, and
  each lane owns its files outright (one owner per shared file per release, listed below).
- **One implementer + one reviewer per bite, reviewing THE BITE.** ⛔ Since 2026-09-29 (user: "6.6.x is not
  just find all the bugs when fixing bugs"): a reviewer's out-of-scope find goes to the *Potential backlog*,
  never automatically into a later release — only the user promotes it. Agents do not sweep the tree for
  unrelated defects; they report a severe one met in passing (security, silent corruption) in one line.
- **At most two `src/` lanes per release, and only ONE of them commits `build/cycc`.** The other commits
  source only; the binary is rebuilt once, at the merge, with fixpoint + seed-derive.
  `build/cycc-native-aarch64` is regenerated ONCE on the merged tree (`cyrius pulsar`, release-gate
  step 1b).
- **A per-lane green is not a merged green** (the 6.6.6 lesson: five green lanes merged into four
  failures). `check.sh`, seed-derive, ARM lockstep, cross-OS on ecb/ach/cass/pi, agnos-qemu where named,
  and the bench all run on the MERGED tree, with the box quiet (`check.sh` goes RED under load until
  6.6.8 bite 8 makes deadline kills say so).
- **CVE ids**: 6.6.7 spends **CVE-46** (bite 1 — a `secret var` in a closure body was never
  zeroised), **CVE-47** (bite 2) and **CVE-48** (bite 4); 6.6.9 spent **CVE-49** (bite 10) and **CVE-50** (bite 12, the `lib/http.cyr` request overflow); 6.6.10 spends **CVE-51**, **CVE-52** and **CVE-53**. Each
  bite bumps the CLAUDE.md counter in the same commit. *(This line first planned CVE-46 for bite 2;
  bite 1's audit finding spent it first, so every later id moved up one.)*

### 6.6.7 — SHIPPED 2026-09-28 (tag `6.6.7` @ `f07395ce`)

All ten bites shipped as planned, in six worktree lanes merged into main; detail is in
`CHANGELOG.md` [6.6.7]. The twelve filed issues it fixed are archived (the daimon clock one by
its bite); each filed repro was re-run on the merged tree. It spent **three** CVE ids, not two:
**CVE-46** (a closure's `secret var` was never zeroised — bite 1), **CVE-47** (a `secret var`
skipped on a tail return — bite 2), **CVE-48** (on agnos a 127.0.0.1 server listened on the
network — bite 4); 6.6.9's planned CVE is therefore **CVE-49**.

⚠ **The merge again found what no lane could** (the 6.6.6 lesson, repeated): each lane's
`check.sh` was green, and the merged tree went red three ways — bite 7 sized an array by an enum
that the fold lane's larger bundles pushed past var index 1024 (6.6.8 bite 1's cap), bite 7's
new derived clock axis caught bite 4's unchecked #95 read, and bite 7's gate expected a
`syscall` adjacent to its number where bite 4 now zeroes `r10` in between.

**⛔ Sibling releases the fold took, by commit — tag each at that commit BEFORE the cyrius 6.6.7
tag:** sandhi **1.10.1** `f93d035` (cut during the fold: macOS EAGAIN is 35, and PE had been
borrowing yukti's `SYS_SOCKET`), vani **1.2.7** `5cdd402`, sigil **3.13.3** `92a5042`, yukti
**2.3.13** `ff97eec`, mabda **4.1.5** `2a9f67c`. sakshi 2.5.5, patra 1.15.0, niyama 1.0.12 and
bayan 1.5.7 were folded from their existing tags.

### 6.6.8 — SHIPPED 2026-09-28 (tag `6.6.8` @ `68eb2661`, a re-cut after CI's Test (AGNOS) job went red on the first tag)

All eleven bites shipped (bite 1b — the nested-emitter and derive follow-ups — included), in six
worktree lanes merged into main; detail in `CHANGELOG.md` [6.6.8]. The seven filed issues it fixed
are archived by their bites. No CVE was spent. **Sibling releases the fold took, by commit — tag
each BEFORE the cyrius 6.6.8 tag:** yukti **2.3.14** `bcc8cb0` (ppoll declines on macOS) and
ganita **1.2.7** `3c15403` (`pow` follows C99 Annex F).

⚠ **The merge found two more lane interactions, again invisible per lane:** bite 7's new
`agnos_process_peer_parity` gate required agnos peers for five host verbs bite 8 added in another
lane, and bite 8's new `check_gate_census` ratchet (gates hard-coding `CC`, measured at 74 on its
own lane) saw 80 once six other lanes' new gates arrived — converted to `${CYCC:-…}` rather than
raising a ratchet that only goes down.

⚠ **aarch64 size tax measured at the merge:** `build/cycc-native-aarch64` `.text` +82,952 B — bite 3's
nine ESYSXLAT rows copied into each of 605 syscall sites (backlog: a shared translation stub).

### 6.6.9 — SHIPPED 2026-09-28 (tag `6.6.9` @ `a5f6691e`)

All twelve bites shipped (bite 12 — `lib/http.cyr`, CVE-50 — added by the user from the 6.6.8 review
finds); detail in `CHANGELOG.md` [6.6.9]. The last ten filed issues are fixed and archived — the open
issue queue is empty. **CVE-49** (bite 10) and **CVE-50** (bite 12); the next free id is 51. No sibling
release. self_compile −17 % (bite 1's global-name index).

⚠ **Merge lessons, third release running:** bite 7 (stdlib self-sufficiency) needed two small hunks in
files lane S2 owned, which S2's bite never picked up — the lane handed over a verified patch instead of
crossing its ownership line, applied at integration; and that same self-sufficiency made a gate's
"file that cannot resolve" fixture (a copy of `lib/fs.cyr`) resolve. When a plan gives one lane's
bite a dependency on another lane's file, name the hand-off in BOTH lanes' specs.

### 6.6.10 — CLOSED 2026-09-29 (awaiting the tags)

All seventeen bites shipped; detail in `CHANGELOG.md` [6.6.10]. **CVE-51** (x86-macOS clock stray write),
**CVE-52** (stray `@`), **CVE-53** (`ws_recv_frame`); the next free id is 54. Nine sibling patch releases
(tag list in `state.md`). The merge had no conflicts — one lane owned every gate registration and every
cross-lane hunk travelled as a named hand-off patch. ⚠ Remaining merge lesson: a ratchet's "final pass"
(the cross-compile allowlist, the alloc census, the gate census) cannot run inside a lane that works in
parallel with the lanes it measures — it is an integration step, and it is now done there.

### 6.6.11 — the 6.6.9 review finds I–K + the 6.6.10 finds that produce wrong results (by the user, 2026-09-29)

The 6.6.9 review finds I–K and the sibling items (placed here 2026-09-28), plus the 6.6.10 finds that
compile wrong code, crash, corrupt memory, or score a failure green. The 6.6.10 lanes filed 212 notes
(implementer, reviewer and fixer each reported the same defects), which deduplicate to the 34 defects in
L–P below; everything else is in 6.6.12. This release opens only after the 6.6.10 tag. Where the guide
currently documents one of these defects as a rule (L4, P1), the fix also deletes that rule.

- **I. Windows** — `lib/fs_win.cyr` `_fs_widen` reads to NUL with no bound (`is_dir`, `dir_list`). The PE
  `SYS_OPEN` reroute widens byte by byte (ASCII, 260 units), so `cyrius.exe` cannot open a non-ASCII or long
  path. The Windows CLI ignores `CYRIUS_RESOLVED=1`. `net.cyr` sockets return -ENOSYS on PE, so `http_*`
  cannot work on Windows at all, and the resolver's POSIX paths become `<drive>:\etc\hosts`.
- **J. stdlib** — `http.cyr`'s Host header drops a non-default port, and `_http_parse_url`'s control-byte
  check is narrower than its comment says. `bench_batch_stop(b, 0)` and `bench_run_batch(…, 0, …)` SIGFPE.
  `load_environ` reads only 8,191 bytes of `/proc/self/environ`. `lib/sync.cyr` has no cx arm, so
  `thread.cyr` cannot compile for cx, and `tls`/`tls_native` overflow the cx codebuf. macOS CLI children do
  not inherit the user's PATH, so `cyrius deps` cannot hash on ecb/ach. The PENDING tier (`log`, `ws`,
  `ws_server`) also lacks first-party definers. `programs/vidya.cyr` alone has 25 undefined fns.
- **K. tools + harness** — Shell gates have no SKIP exit code, so `CYRIUS_CHECK_NO_SKIP` cannot reach them.
  CI's "CLI cross-compile" step is still a hand copy that the census does not cover. `NO_SKIP` does not fail
  a selected run that tallied zero rows. `check_gate_census.sh` and `check_targeted_run_selects.sh` exit 2
  under `bash -eo pipefail`. distlib sidecars depend on the host OS that runs them, and the verify loop's
  6-round cap returns success without a final compile. `cmd_soak`'s step-failure lines fabricate a flat-1
  status. `bench_timer_floor_measured.sh`, `pe_fsync_flushes.sh` and `distlib_profile_sidecar.sh` hard-code
  their tool paths. The capacity row prints a stale `fail@28000fns`. Stale comments: the 4096-cap line in
  `syscalls_x86_64_linux.cyr`, the ganita fold header's `lib/matrix.cyr`, cbt's "is_symlink is 0 on
  Windows", and several gate descriptions.
- **L. struct copies and fields** (src)
  1. `var p: Pt = b.v` (a struct var initialised from a struct-typed field) SIGSEGVs on x86 and aarch64
     (6.6.9 too), and `q = b.v` copies one word. `_try_struct_copy_init` and `_try_aggregate_copy_assign`
     (`src/frontend/parse.cyr`) do not recognise a field source; reuse bite 5's `_fla_want`/`_fsc_*`.
  2. Storing a non-struct value into an odd-sized (3/5/6/7 B) struct-typed field writes 8 bytes and clobbers
     the fields after it (`h.o = 7` zeroes `h.t`/`h.u`). PARSE_FIELD_STORE's width ladder falls through to
     ESTOC. Either refuse the store or write exactly FIELDSZ bytes.
  3. A method whose `self` is a by-value struct of 8 bytes or less receives the receiver's ADDRESS:
     `x.twice()` reads garbage while `Odd_twice(x)` is correct. PARSE_FIELD_LOAD's method arm always pushes
     `&x`.
  4. A struct result of 8 bytes or less from a method or operator is not type-checked against its
     destination (`h.o = y.same()` compiles with a different 3-byte struct). `_sc_post`
     (`parse_fn.cyr:1956`) returns early for `_ret_agg_class == 0`, so record the sid. The fix deletes the
     guide's "not type-checked yet" line (`cyrius-guide.md:433`).
  5. A struct destination assigned from a call that returns a DIFFERENT struct stores one word silently
     (`var p: Pt; p = mkq();` where `mkq(): Q`). `_try_struct_call_assign` (`parse.cyr:2106`) returns 0 on
     the mismatch and the scalar store runs, although the declaration form refuses it. Also reachable
     through generics: `s = mk(r.v)` into a `Box<Pt>` local.
  6. `var y: Q = x;` from a by-value struct parameter passed by address (Q is 24 B) copies garbage (sq 52,
     want 121). A field-by-field copy is correct.
  7. After any `union`, the 8192-entry struct field-pool cap never fires. PARSE_UNION_DEF's fcount `1<<63`
     rides into `ent` and `pooltop` in ADDFIELD/ADDFIELDTYPED (`parse_types.cyr`), so the signed test never
     trips, and writes past the 0x91A000 pool corrupt compiler tables (the symptom is a nonsense
     alloc/cstring error). The fix is to mask bit 63.
  8. `sizeof` and `#assert` use the prefix-only `_scalar_name_width`: `sizeof(i16v8)` is 2 and
     `sizeof(i8zz)` is 1, silently. Use bite 5's whole-name `_field_scalar_width`.
  9. A top-level global typed as a generic struct instance: `var G: W1<Pt> = mkw(gp); w1s(G)` gives 2 (want
     52) because `_refuse_toplevel_pair_init` does not fire, and `G.v.x` (or `gr.v.x = 2` inside a fn) is
     "expected '=', got '.'". Both halves ship here, because the init half is a silently wrong value.
- **M. float typing residuals** (src)
  1. Compound assignment on an f64/f32 GLOBAL is integer arithmetic: `var G: f64 = 1.5; G += 1.0;` adds the
     bits. The compound arm in `parse.cyr` takes the type only from FINDLOCAL, so it needs a GVTYPE lookup.
     In the same arm, `t += 1` on an f64 local gets no kind-1 or kind-4 warning.
  2. The f32 arithmetic arms have no operand-kind check. `f32_from(u) + 1.0` makes EMIT_F32_BINOP combine
     an f32 bit pattern with an f64 literal's bits, and typed f32 vars never had the kind-1 check either.
  3. `var t = p.y` from an f64 field stays i64. The field load is typed F64 but the untyped var does not
     infer it, so `t + t` is an integer add.
  4. A reassigned untyped var keeps its declaration-time kind-3 flag. `var g = 0; g = 1.5; -g` is silent
     (an integer negate of float bits), while `var g = 1.5; g = 7; -g` warns. Re-judge the flag on plain
     assignment, and rewrite the guide's "a later assignment does not change it".
- **N. lexer / diagnostics** (src)
  1. A raw newline inside a string literal does not advance the line counter: the `lex.cyr` string loop
     copies byte 10 without SCLINE. Every later diagnostic, including 6.6.10's lexer file:line:col, is one
     line early per embedded newline. The fix is one line plus a row in `lexer_errors_name_file_line.sh`.
  2. An unknown string escape `"\q"` is stored verbatim (`abq`), while char literals already refuse it. This
     is the CVE-31 class. Survey the ecosystem in the same bite, then refuse it.
  3. Diagnostics located in `src/backend/x86/fixup.cyr` are one line high in the x86 and PE builds. Its
     line 1 maps to no file (it is reported as line 52534 of the includer). The `#@file` bookkeeping for that
     include (`main.cyr:671`, after `pe/emit.cyr`) starts a line early.
  4. A qualified enum access never validates the enum name. `Foo.EB` (Foo undefined) and `E2.EB` (EB is not
     a variant of E2) compile, and since 6.6.10 they also compile in `#assert` and array sizes. Resolve the
     name against GENUMNM and `var_enum_id`, in one place shared with `_enum_atom_idx`.
  5. A `#assert` with no message and no trailing `;` swallows the NEXT line. In a fn body that silently drops
     a `return`, and the fn returns garbage. `_assert_tail` (`parse.cyr:1940`) takes the line from the cursor
     token, which is already on the next line; take it from `GTI(S) - 1` and keep the wrapped
     `#assert X,\n "msg";` form working.
  6. A top-level syntax error is lost when a failing `#assert` follows it: `var x = ;\n#assert 1 == 2;`
     reports only the assert, because the assert-failed path hard-exits before the earlier error prints.
  7. `return mulh64(a, b)` / `return sizeof(i64)` are compiled as a tail call to an undefined fn on every
     backend. PARSE_RETURN's detector (`parse_fn.cyr` ~706-729) takes any `IDENT (…);`, and
     `_tc_must_divert` has no packed-name builtin check.
  8. DCE never reports the fn defined right after an `async fn` as dead (`CYRIUS_DCE_VERBOSE=1`). Determine
     whether this is over-approximation or the coroutine falling through into the next fn, then drop
     `lexer_attribute_word_boundary.sh` F4's literal-list workaround.
- **O. tests (and one tool) that exit 0 when they fail**
  - `tests/tcyr/derive/derive_body_shapes.tcyr` and `tests/tcyr/crossos/derive_accessor_widths.tcyr` define
    `fn main`, call `main();` at top level and end in `var r = assert_summary();`, so the entry calls main
    again and exits with that second run's 0 (a mutation run gave 1 failed, rc 0). The cross-OS leg
    therefore cannot see a failure in the crossos file. Fix both with `return assert_summary();` +
    `syscall(60, main())`, plus a corpus lint that refuses the shape.
  - `tests/tcyr/platform/pwd_grp.tcyr:92` and `tests/tcyr/platform/shadow_pam.tcyr:67` end in
    `var r = assert_summary(); syscall(60, 0);`. Both should exit `r`.
  - A `.tcyr` that dies before `assert_summary` can exit 0 with FAIL rows on stderr. Every tcyr reader
    should require the summary line, not grade on the exit code alone.
  - `cyrius lint` prints `0 warnings` and exits 0 on a file that cycc refuses at the derive stage
    (`#derive(accessors)` on an enum, PP_DERIVE_BAD), because `_lint_msg_is_syntax` (`cbt/commands.cyr`)
    fails only on syntax-class messages. Default: any cycc refusal fails lint.
- **P. async / runtime** (lib)
  1. Under `async_run`, a coroutine whose `await` does not park ends the task with 0 and is never resumed;
     this includes `await inner(..)` of a Future. `_async_step` (`lib/async.cyr:178`) and its macOS,
     Windows and agnos peers mark the task DONE. Keep it READY when `fp == &future_force` and
     `future_pending(arg) == 1`, and delete the guide's "force such a coroutine yourself" rule
     (`cyrius-guide.md:2582`).
  2. The macOS reactor spins at 100 % CPU when a normal wake leaves a READ/WRITE registration armed on a
     still-readable fd (measured on ecb: ~1 s of CPU for a 1 s `async_with_timeout`), because
     `_async_kev_wake` never uses EV_DELETE. Register with EV_ONESHOT, or delete the filter on wake.
  3. macOS `async_run` never closes the runtime's kqueue, which leaks one fd per runtime (the epoll backend
     closes its epfd). `lib/async_macos.cyr:239` currently documents the leak instead of fixing it.
  4. Linux `async_with_timeout(rt, h, 0)` and `async_interval(…, 0, …)` arm an all-zero itimerspec, which
     DISARMS the timerfd (`_async_timerfd`, `lib/async.cyr:783`). The first then has no deadline and the
     second parks forever; macOS treats ms <= 0 as expired or unscheduled. (Found by reading the code;
     measure it first.)
  5. `async_run_process`'s deadline blocks the single-threaded reactor for up to `_PROC_GRACE_MS` (5 s),
     because `proc_kill_tree` sends TERM and then nanosleep-polls. The async path needs a non-blocking reap.
  6. `async_with_timeout` on an `async_spawn_process` handle leaves the child running and unreaped when the
     deadline wins, on both backends: `_async_retire` only drops the registration.
  7. Linux `async_timeout` SIGKILLs only the forked body's pid (`lib/async.cyr` ~1107), so anything the body
     spawned outlives the deadline. Use `proc_kill_tree`.
  8. The Linux capture verbs (`exec_capture_status`, `exec_capture_str`, `run_capture` in
     `lib/process.cyr`): when the child exits on its own and a grandchild holds the pipe, the verb reports -2
     and kills nothing, so the grandchild survives at PPID 1. macOS ends the setsid group (`e815ab0f`) and
     Windows ends the job. Default: the macOS shape, with no subreaper window inside a library verb.
  9. `_regression_kill_tree` (`lib/regression.cyr:585`) kills only the pid off Linux, because
     `_regression_tree_collect` returns 0 there; adopt `proc_kill_tree`'s macOS group kill.
     `process_deadline_tree.tcyr:73`'s whole-tree row can then drop its Linux-only guard.
- **Sibling / ecosystem** — stiva and kavach both declare `struct AuditEntry`, so distlib now refuses stiva's
  sidecar. bote's clean resolution puts the monolithic sigil and the thin sigil-mldsa in one unit. dhvani's
  named dep naad fails a `: stack` return binding. kavach needs re-vendoring in mehman, stiva, aethersafha,
  agnosai and agnostic. sandhi still falls back to a clock-ns DNS TXID when getrandom fails (a CVE-19
  residual). ganita's `f32_sin`/`cos` NaN guard rests on a premise that 6.6.9's trig removed.

### 6.6.12 — the overflow (by the user, 2026-09-29); the batch ENDS here

The real 6.6.10 finds that do not produce wrong results: platform surface, language-surface gaps that are
already loud, stdlib/tool and gate hygiene, the sibling patches, and one line of stale text. This release
opens only after the 6.6.11 tag.

- **Q. platform surface**
  - Five native aarch64 syscalls cannot be reached by number, because ESYSXLAT renumbers x86 compat numbers
    that are also native: setxattr 5→fstat, fsetxattr 7→ppoll, lgetxattr 9→mmap, fgetxattr 10→mprotect,
    fchown 55→getsockopt. Add xattr/statx/getrlimit/fchown wrappers with private-alias-band (1000+N) rows
    and a `tcyr/crossos/` companion. Until then kriya 1.7.2 returns -38 for xattr on aarch64.
  - The raw-literal diagnostic warns on correct native aarch64 numbers inside `#ifdef CYRIUS_ARCH_AARCH64`
    (`syscall(8,…)` getxattr is flagged as "x86_64 lseek", and `syscall(291,…)` statx is flagged too), and
    there is no way to mark a number as native. Separately, 6.6.10's 3-arg `kill` arity skip applies on
    every x86 target, so a wrong 3-arg `kill` on Linux no longer warns. Gate the skip on Mach-O and re-run
    seed-derive (the cybs per-fn cap).
  - x86-macOS has no faccessat route: `EMACHO_SYSXLAT` lacks 269 → 466, so a raw call gets SIGSYS
    (allow-listed in `macho_route_parity.sh`). The arm64-macOS `dup3 24 → dup2 90` route silently drops
    the flags argument, so O_CLOEXEC is lost.
  - x86-macOS `clock_now_ns` is REALTIME (gettimeofday), so it can step under NTP; every other target is
    monotonic. gettimeofday's third argument (the mach_absolute_time out-pointer; `x86/emit.cyr:1302`,
    "HONEST LIMITATION") gives a monotonic source.
  - Windows `_dir_list_into_vec` (`lib/fs_win.cyr`) ends a listing silently when FindNextFileW fails partway.
    Telling that apart from ERROR_NO_MORE_FILES needs a GetLastError PE reroute.
  - cx emits no tail calls, so a 20M-deep tail-recursive fn dies on cxvm with a garbage rc. cxvm treats an
    unknown opcode as a silent no-op (`cx_run` has no trailing `else`, so an older cxvm runs 6.6.10's
    0x6A–0x6D as identity), and it writes through guest address 0 silently.
- **R. language surface** (all loud compile errors today; none produces wrong code)
  - The generic struct literal `Box<Pt>{p, 5}` fails with "undefined variable Box".
  - An explicit generic call as a bare statement (`id<i32>(4);`) fails with "expected '=', got '<'".
  - `f(mk(p).n)` (a field of a call result, used as an argument) fails with "expected ')', got '.'".
  - Indexed element assignment `arr[i] = v` on a typed array (`var arr: i64[4]`, local or global, in any fn)
    fails with "expected '=', got '['".
- **S. stdlib + tools**
  - Null derefs on the out-of-memory path. After `bench_new` refuses its alloc, every `lib/bench.cyr`
    accessor (:491–1089) still dereferences the 0 `b`, and the doc examples at :156, :794 and :858 never
    check it. chrono's `dt_year`…`dt_second` load through a possibly-0 `epoch_to_date()`.
  - `file_read_whole` (`lib/io.cyr:590`) overwrites the negative errno in `*len_out` with 0, so no caller
    can tell a read error from an empty file.
  - cyrius-lsp `_LSP_SYMTAB_CAP` is 4096, and indexing silently stops at the cap. Since 6.6.10 indexes
    every spelling, large includes reach it sooner; make the table growable.
  - cyrlint measures line length in bytes, not columns: a ~93-column box-drawing rule is 200 bytes and trips
    the 120 limit. Count code points.
  - `cyrius_check --tool-path <unknown>` exits 1 without printing anything.
  - The depth-0 declaration reader ends `aethersafha/src/main.cyr` at brace depth 1, so coverage and header
    miss every declaration after that point. Determine whether the reader or the file is wrong.
- **T. gate / harness hygiene**
  - `tests/tcyr/CORPUS_FLOOR` is 250 against a 394-file corpus, so a blind reader could lose about a third
    of the corpus before the floor fires. Raise it.
  - `check_gate_census.sh`'s `CYCC_CEIL=73` can drop to 71 (the count measured on a merge of all lanes), and
    `stdlib_modules_self_sufficient.sh`'s agnos floor can rise from 73 to 74.
  - `check_driver_bounded.sh` leaves two empty `$TMPDIR/cyrcheck.<pid>.0` dirs per run, because the
    driver's `--gate-row` and `--output-row` modes skip `_run_tmp_cleanup()`.
  - `tests/tcyr/text/unicode_normconf.tcyr` opens `tests/data/NormalizationTest.txt` relative to the CWD.
    Run from anywhere else, it SIGSEGVs after its own FAIL; it should exit with the count.
  - `crypto/tls_native_scaffold.tcyr`'s fork and accept4 groups are unguarded for PE and agnos (it sits on
    both allowlists in `tcyr_corpus_cross_compiles.sh`). One guard pass with a named SKIP clears both.
  - `crossos/win_qpc_clock.tcyr` (QPC and GetTickCount64 agree within 20 ms over ~200 ms) failed once on
    cass under sequential ssh load. Widen its tolerance or measure against a quiet window.
- **U. sibling / ecosystem** (each is that repo's next patch release)
  - **kriya** — aarch64 is still unusable. FS_O_* and `fs_opendir_nofollow`'s 0o600000 are x86 flag values,
    and `k_stat` hands callers the x86 `struct stat` layout (st_mode at 24, where aarch64 writes it at 16).
    On pi, `ls -l`, `stat`, `which`, `xargs` and `cp -p` read garbage (kriya roadmap 1.7.4).
  - **yantra** — `_cdp_set_nodelay` (`src/protocol/cdp.cyr`) issues a raw `syscall(54, …)`, the x86
    setsockopt number; use the stdlib wrapper.
  - **52 repos vendor `lib/ws.cyr`** (many also vendor `ws_server.cyr`). They pick up CVE-53 only when they
    re-vendor on ≥ 6.6.10, which is the post-6.6.10 sweep.
  - **majra 2.9.2** — its quirks #6 line ("6.6.10 corrects the inverted suffix") is true: bite 10 landed
    `(reachable call site)` (`x86/fixup.cyr:816`). Only the tag remains.
  - **sigil** — `agnosys_run_*_timeout` (`src/sys_util.cyr`) leave their argv/envp allocs unchecked (the
    alloc census skips vendored folds).
  - **bayan** — `bayan_base64_encode` (`src/base64.cyr:14`) stores into its own refused alloc, so ws.cyr's
    handshake keys SIGSEGV instead of returning 0.
  - **agnos (handed to agnos)** — fork copies `VFS_SEC_WFILE` fd entries by value (`vfs_fd_inherit`,
    `kernel/core/vfs.cyr:171`). Reaping the child then flushes and frees the pool block that the parent's
    live fd still names (`proc.cyr:1913`, `vfs.cyr:286`). 6.6.10's `async_timeout` is the first stdlib fork.
- **Dead code** — `FLIT_DEN` (`src/common/util.cyr:492`) and the FLIT table's unused denom slot (unreachable
  fns 74 → 75), and `_defer_emit_init`'s unreachable return jmp after a coroutine's resume dispatch (5 B per
  coroutine with defers).
- **Stale comments/labels** — vidya `field_notes/attn11.cyml` TRAP 2 ("long float literals mis-parse" has
  been false since 6.6.10, and its `3.0e-3` is a form cyrius never lexed), and cyrlint's "not yet" deferral
  false positive on `lib/async_agnos.cyr:87`.

⛔ **The repair batch ends at 6.6.12** (user, 2026-09-29: "6.6.x is not just find all the bugs when fixing bugs"). From 6.6.13 the minor returns to its planned phases — Phase 2 proposals, then Phase 3 committed ergonomics. Out-of-scope defects found while working a bite go to the *Potential backlog* below, never automatically into the next release; only the user promotes them.

### Sibling follow-ups found at the 6.6.7 fold (each is that repo's next patch release)

- **sigil** — its other Linux-valued errno constants are wrong on Darwin (3.13.3 fixed EAGAIN only).
- **vani** — `vani_drain` / `vani_drop` / `vani_state` mix a `: stack` Result with a single-value return.
- **vani + mabda** — both define a private-in-spirit `_sk_emit_err`, a duplicate fn when both are in scope.
- **yukti / mabda** — both declare `PCI_VENDOR_AMD` with different values.
- **patra** — its raw getrandom sites (bundle `:1085`, `:1111`) skip the Darwin `0 → len` normalisation.
- **sandhi** — its full test suite never runs on macOS (the EAGAIN defect lived there unseen).
- **sakshi** — stale clock comments in its source repo.
- **mirshi** — does not emulate agnos `#95` and writes only the 40-byte `sysinfo` base struct.

### Not placed in 6.6.7–6.6.9

- **Already shipped** (their roadmap bullets are removed below): lexer attribute prefix (6.6.6 bite 5),
  preprocessor directives in strings (6.6.6 bite 4), top-level block closure (6.6.6 bite 3), `cyrius-init`
  on Windows (6.6.6 bite 6), distlib leaf OOM (6.6.3).
- **sankhya DCE bench segfault** — the cyrius fix shipped in 6.6.3; what remains is sankhya's: move its pin
  to ≥ 6.6.3 and restore `CYRIUS_DCE=1` on its CI bench step.
- **DCE compaction on PE / x86 Mach-O / aarch64** — the XL arc below (formerly repair slot `.4`–`.5`).
  **Default: the anchor `src` lane of the release after 6.6.9.**
- **The two 2026-09-20 proposals** (coverage over run programs; fuzz poison through an allocator seam) — Phase 2
  (P5, P6). Their prerequisite defects ship in 6.6.8 bite 9 and 6.6.7 bite 8.
- **ESYSXLAT emits its whole translation chain INLINE at every aarch64 syscall site** — measured at the 6.6.8
  merge: `build/cycc-native-aarch64` `.text` 1,495,592 → 1,578,544 B (+82,952 over 605 `svc` sites, ~137 B
  per site) because 6.6.8 bite 3 added nine rows and every row is copied into every site. Every aarch64
  program pays it, and each new row makes it worse. A shared translation stub (one call per site) would
  cut it to a few bytes a site. Correct today; a size tax, so it is placed here rather than in a release.
- **Fold bundles that are raw-includable** — an XL cross-repo campaign (a distlib change released first, then
  ten sibling regenerations, then a re-vendor); backlog, below.

---

## The shape of v6.6.x

| Phase | Slots | What goes here |
|---|---|---|
| **1 — Repair window** | `.2` – `.6` | ✅ **CLOSED at 6.6.6.** |
| **1b — the consumer batch** | `.7` – `.9` | The 6.6.7 → 6.6.9 batch above. |
| **2 — Proposals** | after the batch | The open proposals, sequenced by their own stated prerequisites. |
| **3 — Committed ergonomics** | after proposals | The v6.6.x "best of the best" language-import list, carried in from `roadmap_6.md`. |

---

## Open arc — DCE cannot compact on PE, x86 Mach-O or aarch64 (the rip-relative repair)

**Arrived from v6.6.1.** `CYRIUS_DCE=1` now declines the whole-program compaction on PE and x86
Mach-O, exactly as it already declines under `_pie_mode`, because both reach a live import/stub
table through a **rip-relative disp32 that the compaction pass does not repair**, and both
compute file geometry *before* elimination runs. Declining was the correct release fix — those
targets emitted a binary that faulted `0xC0000005` before `main` (PE) or SIGSEGV'd on real
Intel-Mac hardware (Mach-O) — but it leaves them on NOP-fill: **correct, and not shrinking.**
ELF still eliminates for real (measured 123,048 → 16,552 B, −86.5%).

**The repair is two things that must land together**, which is why it is scoped at two slots:

1. **Repair the rip-relative shape in `wp_compact`** — when a body is removed, every `disp32`
   whose target is *not* code that moved by the same delta needs re-patching. This is the same
   repair `_pie_mode` needs, so doing it unblocks PIE compaction too; do not build a PE-only
   version of it.
2. **Re-run `_pe_layout(S)` after compaction** (and the Mach-O equivalent) so section geometry,
   RVAs and `PointerToRawData` describe the code that was actually emitted — with the ftype=4
   IAT-reference fixups patched **after** that re-layout, since their displacement is computed
   from `_pe_idata_rva`.

⚠ **Order matters and the current code proves it**: the IAT displacement in the broken build
resolved to RVA `0x39DD` for an IAT the header put at `0x23000` — it had been patched against the
old geometry and then the instruction moved. Fixing geometry without fixing displacements, or the
reverse, produces a binary that looks fine and faults later. That is exactly the shape that cost
three attempts at the v6.5.72 compaction work.

**Acceptance**: `tests/gates/codegen/dce_pe_macho_layout_declines_compaction.sh` is **inverted** —
its axes 1-2 currently assert the payload does *not* move, and on success they must assert PE and
Mach-O shrink *and still run*. Verify by RUNNING on `cass` and `ach`, not by size alone; the
whole defect class is "smaller and broken". Keep axis 3 (ELF still eliminates) unchanged.


**Placement (default taken 2026-09-27): the anchor `src` lane of the release after 6.6.9** — it does not fit
6.6.7–6.6.9 without a third compiler lane. Premise re-checked at the 6.6.7 open: the decline is live at
`src/backend/x86/fixup.cyr:875-876`; `_pe_layout(S)` runs at `fixup.cyr:146` (the comment at `:859` and the
gate header still say "line 123"); the ftype=4 IAT disp32 is baked at `:295-300`, before compaction runs at
`:877-878`. ⚠ **Wider than the slot said**: `wp_compact` also returns 0 for EVERY aarch64 target
(`src/common/ir.cyr:1634`), so arm64 Mach-O and aarch64 ELF never compact either — the same arc, taken
together. Until it lands, the declined-path note should say it declined and why.

---

## Phase 2 — the proposal queue

Six open proposals, sequenced by their own stated prerequisites rather than by size.

### P1 — `cyrius.cyml` as the build tool's actual configuration
[`proposals/2026-09-04-build-tool-manifest-integration.md`](proposals/2026-09-04-build-tool-manifest-integration.md)

Filed 2026-09-04, 🟡 OPEN. **Sequence it first, and adjacent to `.2`** — both are about the CLI
honouring its own manifest, and `.2`'s guard needs to read the declared `src`/`entry` key, which
is precisely the surface this proposal is about.

⭐ **The lesson it already records is the reason it ranks first**: the v6.5.49 slice shipped
**inert**. Its `[build]` path fallback read `src`, the key *this* repo happens to use — but of
125 `cyrius.cyml` files across `~/Repos`, **120 declare `entry` and 5 declare `src`**, one of the
five being cyrius itself. So the feature presented as *"does not exist"* to 96% of the ecosystem,
and **its gate passed the whole time because the gate's fixture manifest was written with the
same key the implementation read.** Any work here must gate against a fixture that does *not*
share the implementation's assumptions.

### P2 — Embed data files as source strings (`[embed]` / assets manifest)
[`proposals/2026-08-10-embed-data-files-as-source-strings.md`](proposals/2026-08-10-embed-data-files-as-source-strings.md)

Ergonomics, not capability — the generated-`.cyr` idiom already works and is fleet-wide, and
agnosai ships its own generator, so nothing is blocked. **Its prerequisite has cleared**:
`2026-06-25-source-level-version-constant` shipped at v6.5.21, and `PP_EMIT_PKGVER`
(`src/frontend/lex_pp.cyr`) is the template for a `#@embed` arm.

⚠ **Hard constraint learned at `.21`**: an injected directive must emit **ZERO newlines** (merge
onto the following source line) or it shifts every `<source>` diagnostic by one — a 1-for-1 line
replacement is **not** line-neutral.

### P3 — Compile-time evaluation (`const fn` / const-eval)
[`proposals/2026-07-05-const-eval-comptime.md`](proposals/2026-07-05-const-eval-comptime.md)

**The rung was already chosen 2026-07-07** — option 1 `const fn` primary, option 3 `#phf`
fallback, option 4 (a general const-eval VM) declined. No maintainer decision is outstanding, and
a first triage pass that labelled this "blocked on maintainer" was refuted on re-check. This is
also **item 2 of the committed ergonomics list below** — the proposal and the roadmap row are the
same work, which is why it sits at the phase 2/3 boundary rather than being listed twice.

⚠ It reuses the `ir_const_fold` fixpoint (`src/common/ir.cyr`), so it must land **after** any
work that rewrites that pass, or the churn is paid twice.

### P4 — test-only stdlib leaves, instead of hiding them from the umbrella scan
[`proposals/2026-09-16-declare-test-only-stdlib-leaves-instead-of-hiding-them-from-the-umbrella-scan.md`](proposals/2026-09-16-declare-test-only-stdlib-leaves-instead-of-hiding-them-from-the-umbrella-scan.md)

Filed 2026-09-16 by **rekha 0.4.4**, 🟡 OPEN. Nothing is blocked — rekha shipped the workaround —
so rank it by appetite, though it is **adjacent to P1**: it is the same complaint, that a
manifest does not say what the tool actually reads.

`dist/<pkg>.deps` unions the include scan of **`src/lib.cyr`** (path hardcoded at
`cbt/commands.cyr:3903`) with `[deps] stdlib`, so a harness-only leaf has nowhere to live that
is not published. rekha carried **nine** leaves for a bundle that calls `strlen` + `memcpy`;
consumers vendored eight leaves of nothing for four releases. The fix — move the harness
includes into `programs/prelude.cyr`, a file the scan does not read — cut the sidecar to
`string alloc` with **byte-identical** bundles, and is the discomfort being reported: *which
file an include sits in* decides what every downstream consumer must vendor.

⭐ **`_distlib_verify_leaves` is the part that works** and the proposal explicitly does not touch
it — it derived `alloc` unaided, because `lib/string.cyr` calls `alloc()` and declares no include
for it. Option 3 in the filing is to trust it as the *sole* authority and delete the two
over-reporting channels, which would have produced rekha's correct answer with no declaration
discipline at all.

⚠ **Two measured notes from the filing that outlive whatever shape this takes.** (a) Auto-prepend
puts every resolved leaf in scope, so a package's own tree **cannot** check its own sidecar — a
program with no includes at all compiles while calling `alloc`/`strlen`/`vec_new`, and a
"compile it the way a consumer does" suite therefore passes a sidecar that omits a needed leaf.
Only `_skip_deps = 1` catches it. (b) `_distlib_verify_leaves`' header reasons that
over-reporting is the safe direction; that holds for a *misspelled* leaf (hard resolver error)
but not for a *real* leaf that is merely unnecessary, which is silent. Over-reporting is
quieter, not safer.

### P5 — `cyrius coverage` over RUN programs, not only `.tcyr` suites
[`proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md`](proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md)

Filed 2026-09-20 by **rekha 0.4.12** (25 self-checking `programs/*_test.cyr`, ~13,000 lines of assertions,
coverage reported as ~0 %). ⚠ **Its prerequisite ships first**: 6.6.8 bite 9 fixes how coverage COUNTS
(substring and comment matches, a denominator that drops public fns), and extending the corpus before that
would widen a number that is already wrong. The open scope question — a text-reference corpus versus
execution/branch coverage — is the proposal's, and gets asked when this slot opens. Size: M on top of 6.6.8.

### P6 — `cyrius fuzz --poison` through a custom allocator seam
[`proposals/2026-09-20-fuzz-poison-should-follow-a-custom-allocator-seam.md`](proposals/2026-09-20-fuzz-poison-should-follow-a-custom-allocator-seam.md)

Filed 2026-09-20 by **rekha 0.4.12**, which parses untrusted font bytes through sadish's `sd_alloc` seam and
hand-built a 2,100-line substitute because `--poison` only redzones the freelist. The overlapping piece —
freelist poison comments that no longer describe the code, and a `--poison … ACTIVE` message that claims
coverage it does not have — ships in 6.6.7 bite 8. The design fork (a redzone/fill seam versus guard-page
faulting) is the proposal's. Size: M.

---

## Phase 3 — the committed ergonomics list

**Theme set 2026-07-07 (user, horizon session).** RISC-V rv64 — previously this minor's theme —
was re-homed to v6.7.x/v6.8.x: hardware is in hand, but a 7th platform is deliberately held while
*"still heavy quality and ergonomic improvements [are] on the horizon."* v6.6.x instead takes the
modern-language feature imports that fit the assembly-up identity — **no GC, no hidden control
flow you cannot disassemble.**

1. ✅ **SHIPPED v6.6.0 — `Result` / `Option` / `Either` are the value form.** The one breaking
   change in the minor, at the front of it because everything else is additive. Detail in the
   CHANGELOG; do not re-plan it.
2. **`const fn` — the const-eval ladder, option 1.** See **P3** above; same work, listed there
   with its sequencing constraint.
3. **Opt-in bounds-checked memory mode** (`CYRIUS_BOUNDS` / `#bounds`) — designed in the v6.3.x
   plan, never shipped. Verified live: `CYRIUS_BOUNDS`, `#bounds` and `_bounds_check` find **0**
   hits in `src/`. The sanitizer story that makes footguns findable at their source. **OFF by
   default** — assembly-up: raw stores stay raw in release builds. Premise-check the 0-hit count
   at slot entry rather than trusting this line.
4. **Trait-bounded generics** — the post-monomorphization ceiling. **DEMAND-GATED tail**: pulls
   in only if consumer pressure materialises by the time the slot opens. Fix the
   **multi-type-param struct-type-arg residual** first (single-tparam struct type-args shipped
   v6.3.38–.39; the residual is only the mixed multi-tparam combo).

~~`defer` / scope-exit~~ and ~~per-block scoping + shadowing~~ were struck 2026-07-29: **both
already shipped** (`defer` at v3.8.0; block scoping verified by running the compiler). They sat
here as pending work for features that had existed for majors. What remains of the scoping row —
that a **same-scope** redeclaration is a hard error — is the documented rule, not a footgun.

**Explicitly NOT imported** (decided 2026-07-07): borrow-checker-style lifetimes (wrong fit for
the trust model and the single-pass design), a general const-eval VM, exceptions of any kind.

---

## Potential backlog — 6.x-cycle, unscheduled (NOT parked to 7.x)

Real 6.x-line work without a committed slot; pulled into a release the moment a consumer or
priority surfaces. **These are technical items → they stay in the 6.x cycle, never 7.x.**

- **`lib/net.cyr` §4 — per-arch socket syscall peers.** The issue is ARCHIVED (`✅ RESOLVED
  v6.5.7 + v6.5.11`) and was closed deliberately without its §4, so the sharp edge is gone but
  the work is unshipped: `lib/net.cyr` still carries bare x86 numbers with `grep -c CYRIUS_ARCH`
  → **0**, working because nine `ESYSXLAT` x86-compat rows remap them. That remap is
  **load-bearing for 51 ecosystem repos** — this is a migration, not a deletion.
- **`lib/net.cyr` AF_UNIX surface** — a yes/no design call, not a defect: whether `net.cyr` grows
  a Unix-domain socket surface alongside INET. Nothing blocks on it.
- **DRY the per-target pass-1/pass-2 top-level scanners** — `ls src/main*.cyr` = **7** forks with
  no shared pass-1 dispatch helper. A recurring-bug class, not cosmetics: `#io` v5.8.20, `#pure`
  v6.2.2, and the v6.4.26 trap where a new `E*_PE` reroute needed return-0 stubs in aarch64 + cx
  and only `cass`'s `cycc_cx` caught the miss. Logic-preserving ⇒ gate is byte-identical
  self-host on all four hosts + seed-derive. Premise-check the fork count at slot entry.
- **DWARF debug-info emission** — backend/codegen work; slot it when a real debugger story is
  needed. Distinct from the DX diagnostics arc, which was only the error-reporting layer.
- **Incremental compilation** — unpin condition: reconsider when cycc self-host crosses ~2 s. It
  is **731–734 ms at 6.6.1** after 150+ releases, so the whole-program model is nowhere near the
  threshold. ⚠ Read the trend with care: the same binary has measured a 52 ms spread across three
  consecutive runs — **wider than most release-over-release deltas** — so a single number carries
  no signal. Every release's mandatory bench run IS the report.
- **`ir_dce` / `ir_dead_store` uncapped wrappers and `CLASSIFY_CF` / `CF_TARGET`** — decide
  wire-or-delete. Leaving a third option open is how they survived two closeouts.
- **Bare `var a[N]` byte-vs-slot convention** — a design decision, not an arc. The typed spelling
  `var a: T[N]` shipped v6.2.1 and resolved the common case; what stays undecided is whether to
  lint the address-taken bare-local per-slot idiom.
- **Reclaim the FREED compiler-state scalar holes** (fill-as-you-go, not a slot). Policy: the
  next new compiler-state scalar goes into a hole rather than growing the band. **Cite the live
  count** (`grep -n FREED src/main.cyr`) and the heap map; do not maintain an enumerated list that
  goes stale every minor.
- **`tantu` runtime extraction** — the async runtime lib → its own repo. Repo name reserved; a
  future-**minor** deliverable, still 6.x. **NOT sequenced, and not "next".**
- **Auto-vectorization of scalar SOA loops** — item 4 of the SIMD filing's own fix list, which
  that file already calls "longer term".

- **Fold bundles that are raw-includable** — found at the 6.6.7 triage: `log`, `ws` and `ws_server` cannot be
  included alone because the fold bundles they depend on strip their own includes, so the stdlib
  self-sufficiency sweep (6.6.9 bite 7) carries them as a named PENDING tier. The real fix is a distlib
  change released in cyrius first, then ten sibling regenerations + releases, then a re-vendor — an XL
  cross-repo campaign, so it is not packed into 6.6.7–6.6.9.
- **Nine syscall families consumers still hand-roll, unnamed by the stdlib** — the widened
  surface v6.6.5 measured and deliberately did NOT ship. Per-family reasons, consumers and
  collision analysis live in the table of
  [`issues/archived/2026-09-17-thoth-memfd-ftruncate-sendmsg-unnamed-pass-through-on-aarch64.md`](issues/archived/2026-09-17-thoth-memfd-ftruncate-sendmsg-unnamed-pass-through-on-aarch64.md)
  ("Not fixed, deliberately — (b)"). **Pinned here, not left in an archived file**, because a
  deferral is real only when it is pinned somewhere still open. ⛔ **They are in the exact silent
  class thoth filed**: `_SYSX_MEANT` only carries numbers named in BOTH peers, so a NAMELESS
  number produces **no warning at all** (measured: raw 160 on the aarch64 fork warns nothing).
  Two tiers:
  - ⭐ **Tier 1 SHIPPED at 6.6.8 bite 3** — kavach filed for `unshare`/`chroot`
    ([`issues/archived/2026-09-25-kavach-unshare-chroot-unnamed-aarch64-chroot-unreachable.md`](issues/archived/2026-09-25-kavach-unshare-chroot-unnamed-aarch64-chroot-unreachable.md)),
    and shakti is broken on aarch64 today, so `capget`/`capset` and `process_vm_*` ride with it.
  - **No technical blocker, held only as API surface nobody filed for** — `capget`/`capset`
    (125/126 → 90/91, consumers kybernet + shakti), `chroot` (161 → 51, kavach — the row must sit
    BELOW `51 → 204`), `unshare` (272 → 97, kavach), `process_vm_readv`/`writev` (310/311 →
    270/271, mirshi). Each needs a Darwin route-or-decline, and this release's open concern is
    that three Darwin numbers were derived from neighbouring rows rather than an SDK read — so
    take these on a slot that has an ecb/ach leg, not as a tail-end addition.
  - **Concrete blockers** — `ptrace` (101 is the PRODUCT of this release's `35 → 101`),
    `sched_getaffinity` (204 is the product of `51 → 204`), `pread64`/`pwrite64` (17 is the
    product of `79 → 17` and aarch64-native getcwd → needs the ≥1000 alias band), and the
    `rlimit` family (aarch64 has only `prlimit64`, with a different arg list → an arg-shifting
    row, real hand-assembly).
  - **Acceptance**: every family named in `lib/syscalls_linux_common.cyr` (or the peer that owns
    it) with a Darwin arm, a row whose placement `esysxlat_row_order.sh` passes, and a runtime
    assertion in `tests/tcyr/crossos/` that fails when the number is wrong — the three tests
    v6.6.5 itself had to add.

## 7.x — public-release ONLY

**Language book** (reference/guide finalization) + **legal** (licensing / public-release prep).
**No codegen, runtime, or platform work ever lives here — if it compiles code, it is 6.x.**

---

## Open questions — standing defaults, not a queue

⛔ **This section was once titled "owed to the maintainer" and that framing is banned here. There
is nobody to owe: the maintainer is the person reading this.** A question parked as "owed" is a
deferral to nobody, and it is how several of these sat for months. The rule: **each item carries
a stated default and the work starts under it**; where a genuine fork remains it gets ASKED, in
one line, that turn — not recorded here and left.

The proof is on the record: `darshana-aarch64-syscall-shadow` sat as *"needs a call on where a
~350-row table lives"* until the call was simply taken (**generate it from the stdlib peers**),
whereupon it became 43 derived rows and shipped at `.51`. Assume the same of anything below.

1. **The self_compile budget — ANSWERED (user, 2026-07-29): the later performance track owns it.**
   The budget gets set as part of that track rather than pinned up front. Input for whoever opens
   it: **731–734 ms · 1,247,608 B at 6.6.1**. A previously-floated candidate pair was *≤700 ms and
   ≤1.20 MB at minor close* — ⚠ **both halves are now exceeded**, so that pair is an input to
   re-decide, not a target that was missed. Review together with item 2.
2. **The self-compile growth-tax audit — ANSWERED (user, 2026-07-29): likely dropped, but
   re-review WITH item 1's performance track**, the two being the same subject. Explicitly *not*
   silently dropped — parked against that track's opening review, which decides whether it still
   earns a bite. Record the outcome here either way.
3. **macOS concurrency ordering.** Real platform work with a genuinely broken verb on a gate
   host, so it cannot be dropped — but it has **no consumer waiting**, it mirrors an
   already-shipped split (`thread_win`), and the crossos guards mean it cannot rot silently.
   **Default: keep it last in the minor**; pull it forward if a consumer appears.

*(Former item 3 — per-item `private` — was never a question. It is a live defect and is now
slot `.3` above. Former item 2, the bare-metal forbidden-module check, SHIPPED at v6.5.24 after
this section had carried it as "never built" for thirty releases.)*

---

## Standing notes — traps this minor must not re-learn

- **The `PARSE_RETURN` tail path has skipped a `PARSE_FNCALL` transformation FOUR times**:
  v6.3.36 (plain-struct params), v6.4.53 (value-form SIMD params), v6.5.1 (overload dispatch),
  v6.5.2 (the cstring-literal check). Each fixed with the same narrow divert — the `_cfo`
  escalation shape, *"declared fixed, fourth occurrence in a path nobody enumerated"*. **Any new
  `PARSE_FNCALL`-resident transformation must be grepped against the tail path before it ships**
  — grep the SHAPE, not the operator.
  **FIFTH occurrence (6.6.7 bite 2): `defer`.** The tail path skipped the EPILOGUE's obligation,
  not PARSE_FNCALL's — every `return f(..);` in a fn with a `defer`/`secret var` jumped past the
  defer walker (CVE-47). By then the arm carried fifteen bolted-on diverts, not four; they are one
  predicate now (`_tc_must_divert`, parse_fn.cyr), so a new obligation is a new line THERE. And
  the walker the divert lands on must keep the whole return convention:
  **`EDEFER_SAVE`/`EDEFER_RESTORE` must preserve every return register of every return
  convention on x86, aarch64 AND cx** (x86: rax, rdx, r8, xmm0, xmm1; aarch64: x0-x3, q0, q1;
  cx: r0-r5) — a new return class that adds a register adds it there.
- **A filing's target list is a report about what the reporter builds, not about the bug.** The
  v6.6.1 DCE issue said *"PE / `--win` target only"*; x86 Mach-O shared the code path and was
  crashing on real Intel-Mac hardware, unreported, because the reporter does not build that
  platform. **Reproduce on every host that shares the path before scoping the fix.**
- **An all-identical codegen differential is not evidence a fix is inert — it is evidence of a
  corpus blind spot.** Three consecutive releases measured 0 diffs on real wrong-answer fixes.
  When a fix measures 0 diffs, add the shape to the corpus in the same release.
- **A green CI checkmark is not verification.** The macOS compiler self-host rotted for ~9 minors
  behind a job named "Mach-O ARM64 Native ✓" that only ran hello-world. Run the compiler on the
  hardware.
- **A "found by ports" test is worth more than the gate that says the code compiles.** v6.5.7's
  compile-only wrapper gate proved the wrappers *compile* on five targets — most of the risk, none
  of the bugs. The one `.tcyr` that RAN them found **seven** defects, five of which were half-fixes
  that stopped at the first symptom. Whenever a slot adds a platform-facing verb, the
  `tests/tcyr/crossos/` file is the deliverable, not the nice-to-have.
- **A gate fixture in the wrong order is a vacuous gate**, and a gate whose fixture shares the
  implementation's assumption proves nothing at all (the v6.5.49 `entry`/`src` case). Mutation-prove
  the gate *and* check that the mutation is reachable.
- **When a rule in `CLAUDE.md` tells you to work around codegen, the rule is the bug report.** The
  retired "≤6 args" rule was a Win64 codegen P0 in disguise for about a year, and it got cited to
  file against *sigil*. This is the language repo: when the compiler cannot compile valid cyrius,
  fix the compiler. Premise-check **rules**, not just pins.
- **Re-derive every count in this file at slot entry.** The head line above was version-stamped
  correctly and wrong in five metrics simultaneously; the previous edition carried a gate count
  seven higher than the tree. A number in a roadmap has nothing checking it.

---

## Discipline (per [cycle-discipline.md](cycle-discipline.md))

- **Atomic commits, packed releases.** One logical change per commit; a release bundles many.
- **A bug ships complete** — no granularity by gnarliness, no slicing the hard half into the next
  patch.
- **Only the user pivots focus.** Surface findings; never unilaterally redirect or defer.
- **Release gate GREEN before every `.NN`** — self-host fixpoint · seed-derive · check.sh ·
  cross-OS on ecb/ach/cass/pi (REAL hardware) · bench. Never tag with the gate RED.
- **Benchmark every release**, recording self_compile + cycc size in the CHANGELOG entry.
- **An audit's output is fixes, not a backlog.** File only when the fix genuinely cannot pack —
  and name the reason.
