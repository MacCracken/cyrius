# Cyrius Development Roadmap — v6.7.x (active minor)

**Scope** — the **active minor only** (v6.7.x, the LANGUAGE minor): what is left of its release sequence, the spec
of each remaining feature, the Break 2 candidates, the folded-stdlib follow-ups and the unscheduled 6.x backlog.
Shipped work does not stay here: each release's record, with the user's decisions, is its
[CHANGELOG.md](../../CHANGELOG.md) entry (traits: [ADR-007](../adr/007-traits.md)); one line per release is in
[completed-phases.md](completed-phases.md). The minors after this one are in [roadmap_6.md](roadmap_6.md), the
unpinned watching list is [roadmap-future.md](roadmap-future.md), volatile state is [state.md](state.md).

> ⛔ **Consumer work is never tracked here** (CLAUDE.md, top rule — user, 2026-10-08). This file holds the language,
> its toolchain and the folded stdlibs (what `lib/` vendors). A consumer's follow-ups live in that consumer's own
> roadmap — the last ones were moved out on 2026-10-08 — and a consumer meets a cyrius change at its own pin bump,
> through the CHANGELOG and [ecosystem-migration.md](ecosystem-migration.md). agnos is a consumer.

## Where we are

**Current head: v6.7.6** (2026-10-08) — Break 1 shipped · cycc **1,806,240 B** · `.text` **1,612,016** · `cycc-native-aarch64` **1,601,032 B** · **537** `.tcyr`, **243** in `crossos/` · **106** `lib/*.cyr` · **441** shell gates under `tests/gates/<bucket>/` · api-surface **5,828** · **0** open issues · **1** open proposal · next ledger id **CYRIUS-2026-0036**

> Every figure above is DERIVED (2026-10-08), never carried. `version-bump.sh` rewrites only the stamp's version and
> the `(…)` after it — re-derive the rest at each release (`find tests/gates -name '*.sh' | wc -l`, …). Keep the stamp
> at the start of its line with no nested parentheses in its parenthetical, or
> `tests/gates/toolchain/version_bump_doc_anchors.sh` goes red.

v6.6.x closed at 6.6.20. 6.7.0–6.7.6 shipped (2026-10-07 → 2026-10-08): [completed-phases.md](completed-phases.md)
§ *v6.7.x*.

## The v6.7.x operating rule (user, 2026-10-07)

1. **Language only between the breaks.** A feature release carries language features and nothing else. What it finds
   is FILED to the backlog below, with a repro, the same turn; it is fixed in the release only when the feature cannot
   ship around it (a prerequisite bug). A P0 security finding is reported the turn it is found — whether it interrupts
   the arc is the user's call.
2. **Catch-up breaks clear the backlog.** Break 1 was 6.7.6. Break 2 comes after the remaining features, before the
   closeout; the user picks its items.
3. **Every language decision is the user's** — asked at the arc's start, recorded with its date, never a lane's
   "default" (CLAUDE.md *Execution integrity*).
4. **Every new syntax ships with** a `tests/tcyr/crossos/` file (it runs on ecb / ach / cass / pi), a guide section and a
   vidya entry.

## Release sequence

| Release | Content |
|---|---|
| 6.7.0 – 6.7.6 | ✅ shipped — A traits · C3 trait-bounded generics · B1 `const` + C1 `const fn` · B2 `bool` · B3 the if-expression · B5 `loop` / `do` + B8 `OP=` on every lvalue · the W2 stdlib wave + Break 1 |
| next | the remaining features, one or two releases each, decisions asked at each start: **B4** tuples · **B6** default + named arguments · **B7** narrow struct fields · **C2** the bounds-checked mode (+ P5 execution coverage) · **checked `dyn`** |
| Break 2 | catch-up — the user picks from the candidates below |
| closeout | the closeout checklist ([cycle-discipline.md](cycle-discipline.md)) — the checklist, not an audit campaign |

## Spec — the remaining features

⚠ Every new keyword is a new reserved word (`IS_KEYWORD_TOK`).

- **B4 — tuples as values.** `var t = (1, 2); t.0` — proposed as sugar over an anonymous struct (layout and ABI
  unchanged; multi-return keeps its register pair). Asked at B4's start.
- **B6 — default and named arguments.** `fn f(a, b = 2)` and `f(a: 1, b: 2)`; the v6.5.1 arity check becomes
  min..max. Overloading by arity stays out (v6.5.1: a count mismatch is never intentional).
- **B7 — narrow unsigned and `f32` struct fields.** Today `u8` / `u16` / `u32` / `f32` fields take a full word;
  narrowing changes the LAYOUT of every struct that declares one — an ABI change. `lib/` declares none; cyrius's own
  tcyr files (23 fields) change in the release. It ships with its migration written up in the CHANGELOG and
  [ecosystem-migration.md](ecosystem-migration.md) — never silently.
- **C2 — the opt-in bounds-checked memory mode** (`CYRIUS_BOUNDS` / `#bounds`, OFF by default). 6.6.12 shipped the
  unchecked half for integer-element `var a: T[N]`; still to do: `*T` pointer subscripts, slice writes and the
  checked mode itself. The stdlib must run clean under it (what it trips is a stdlib repair for the next break).
  **With it, proposal P5's execution half**
  ([proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md](proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md);
  P5-A shipped in 6.6.17) — the same insertion point and build-flag plumbing. The bare-local-array slot-write lint
  (backlog, *Tooling*) may fold in here.
- **Checked `dyn` — DECIDED (user, 2026-10-07).** Static dispatch stays the default (ADR-004). `o: dyn Show` is an
  ordinary 16-byte `{data, vtable}` struct (ADR-002's one-word model holds); the compiler builds and VERIFIES the
  vtable from `impl Show for T`, and `o.show()` is an indirect call visible in the declared type. Why: the run-time
  vtables `lib/trait.cyr` and hand-rolled code build are unchecked — a wrong slot or a missing method is a crash.

## Break 2 — candidates (premise-checked at the 6.7.6 open, 2026-10-08; the user picks)

- **Compiler**
  - Generic inference does not see through a generic STRUCT parameter: `gx(b)` for `fn gx<T>(b: Box<T>)` with
    `b: Box<Pt>` resolves the base `gx` (T = i64), refused as a struct mismatch since 6.7.3; `gx<Pt>(b)` works. Likely
    `_gen_infer_tp`; gate row R18b pins the refusal.
  - A bare `const` or enum-constant name as a statement is reported as an assignment (`N;` → "cannot assign to const
    'N'"): `_PARSE_STMT_IMPL` runs the lvalue check before it has seen `=` / `OP=`. Cosmetic; changing it changes a
    6.7.2 diagnostic.
  - A redeclared global read inside its own bool redeclaration reads as boolean (`var G = 5; var G: bool = G;` exits
    5). The fix is a redeclaration rule (refuse a redeclaration that changes bool-ness) — the user's call.
  - `#pure`'s `#io` / `#alloc` check reads the callee's flags at the call, so a call to an `#io` fn defined LATER is
    silent; reuse the const-fn pass-1 record.
  - `asm { in al, dx; }` is refused because `in` is keyword 76, so the `ASM_IN` emitter arm is unreachable (the guide
    documents the form).
  - In an x86 `kernel;` build, float-literal global scalars (`var G: f64 = 1.5;`) are dead stores after the program;
    bake them (6.7.2's evaluator gives the f64 bits).
  - Inside an aarch64 region (`#@a+`), a raw literal that HAS an ESYSXLAT x86-compat row is translated with no warning
    (`syscall(9, ..)` meant as lgetxattr runs mmap); the native spelling is the 1000+N alias.
  - The `ptrace` native-declaration decision (roadmap_6.md § *syscall families*).
- **Tooling**
  - `scripts/ci.sh` cannot install a real release tarball: release.yml packs a top directory, ci.sh globs
    `versions/<v>/bin/*` and finds nothing ("cycc not found"); the only gate that runs it feeds it a fabricated layout.
  - install.sh's source-bootstrap path ships no `cyrius-init-templates` (only the refresh-only and tarball paths copy
    them), so `cyrius init` / `port` lose their templates there. A two-line copy plus a gate row.
  - api-surface's line scanner resets its string state at every newline: a `{` on a raw line of a multi-line string
    empties the snapshot for the rest of the file, and a `fn` line there is listed as public (`_asf_lexst_at` already
    models strings across lines).
  - `cyrius deps --verify` on a CRLF checkout of a committed `lib/` (`core.autocrlf=true`) reports a mismatch for every
    file — the lock hashes the LF bytes. Remedy today: `.gitattributes` `lib/** -text`. Normalise or document.
  - `cyrius deps` / `build` run after a pin move but BEFORE `lib sync --full` stamp the new pin over lock rows of files
    `deps` does not vendor, and `lib sync` then refuses (it names `--relock`; the loud refusal shipped in 6.6.17).
  - A killed `cyrius` run leaves a NON-EMPTY `cyrius-<pid>` dir in `/tmp` that nothing reaps (CLN-03 reaps only empty
    dead-pid dirs). Open: whether a non-empty one past an age bound is reaped too, and which runs land in `/tmp`
    although `TMPDIR` is exported.
- **Platform**
  - The `[embed]` link race (E-S3 residual). Windows keeps the per-component reparse-point check plus a whole-path
    `O_NOFOLLOW` open, so a directory swapped for a junction between them is followed — fix with
    `GetFinalPathNameByHandleW` on the opened handle + containment (a new PE reroute). arm64 macOS reroutes
    `SYS_OPENAT` 56 to BSD `open`, DROPPING the dirfd — it needs a dirfd-preserving route and a `crossos/` companion.
    Needs cass and ecb.
  - `tests/win/async_iocp_pe.cyr` on cass returns 1 at step 2 (`async_with_timeout`) under a plain `cmd /c`; the
    release gate's `cmd /v /c` form exits 42.
  - The Windows trust store (CYRIUS-2026-0020's *Not covered*): CurrentUser `ROOT` under the ProtectedRoots policy is
    unverified; the auto-updated disallowed CTL is not read; a root with a dated distrust is refused whole; roots
    Windows has not fetched yet are invisible.
- **TLS conformance, as one bite**: the 1.3 ECDSA arms of `_tn_verify_sig_scheme` do not bind the leaf's curve to the
  scheme (RFC 8446 §4.2.3); the 1.3 CertificateVerify and 1.2 ServerKeyExchange length checks use `>`, so trailing
  bytes are accepted; the 1.3 client accepts a ServerHello (likely EncryptedExtensions too) carrying an extension it
  never offered (the walk must still admit pre_shared_key on resumption). Riding along: the 1.2 client does not check
  the server certificate's curve against its supported_groups; the 1.2 server takes a `legacy_session_id` over 32
  bytes; four 1.2-client ServerKeyExchange checks (`lib/tls_native_hs12.cyr` ~679 / 688 / 691 / 711) have no test that
  fails without them.
- **The live store** (the user's to run — it writes `~/.cyrius`): `sh scripts/verify-store.sh --restore <v>` for the 16
  slots whose `bin/cybs` is a stale 12,344 B (6.6.3–6.6.9, 6.6.11–6.6.19).

## Folded-stdlib follow-ups (cyrius's own work)

The twelve folds — sakshi, sigil, bayan, sandhi, ganita, niyama, mabda, vani, yantra, yukti, patra, sankoch — are the
language's own stdlib. A fix lands in the fold's SOURCE repo and is released there, then re-vendored byte-identical
(`cmp` against the tag's `dist/`) with its `docs/ecosystem.md` row updated. Each fold's own roadmap holds its longer
list (W2 left there: public `const` / `bool` sweeps in each repo's own minor, traits for hand-rolled dispatch after
checked `dyn`, sigil 3.14.0's cbank retirement, …). Open here:

- **yantra** — its e2e `.tcyr` files include `src/mobile.cyr` / `src/web.cyr`, which call
  `yantra_tls_pin_verify_ed25519` / `_hybrid`, without `src/security.cyr`: an undefined-function warning in the Android
  / iOS test builds (results unaffected, 4/4 each).
- **sandhi** — an end-to-end session-resumption test on the libssl backend (declined by default in W2 — libssl
  retires at sandhi 2.0; in sandhi's roadmap).
- **What the folds asked of cyrius's `lib/`**: a public length-bounded `f64_parse` (bayan B-4) · a `ppoll` wrapper and
  agnos `ioctl` / `fstatat` stubs (yukti) · an `xflock` / `LockFileEx` route on Windows (patra crash recovery) ·
  `#derive(Serialize)` cstring fields (sigil) · `sock_set_nodelay` with a real Windows route — `sys_setsockopt` is a
  -38 stub on Windows although `net.cyr` reaches setsockopt through ws2_32 (0xF032), so `TCP_NODELAY` is never set on
  PE (yantra) · the public-constants-are-`const` migration of cyrius `lib/` (302 names — a user-placed arc with a
  per-name collision survey).
- **Constraints on any fold release**: never change the fold API cyrius's own `lib/` calls (sigil's 73 fns, 8 of them
  private `_x509_*` / `_ecdsa_*` used by `tls_native_hs12` / `hs13` / `tls.cyr`; sakshi's 6 in `log.cyr`; bayan
  `base64_encode` in `ws` / `ws_server`; sandhi `sandhi_server_find_header` in `ws_server`). cyrius must not make the
  stdlib internals the folds use `private` (bayan `_sb_grow_a` / `_sb_die`; niyama `_uc_decode_utf8` /
  `_uc_decompose_cp_recursive` / `_uc_emit_utf8`; ganita `_f64_rem_pio2`). A `const` beside a same-name `var` is a
  hard error (sandhi `HTTP_OK` / `HTTP_NOT_FOUND` against `lib/http.cyr` is why sandhi's public consts wait). Adopting
  6.7.x syntax raises a fold's minimum toolchain. yukti pulls sakshi and patra as git tags, so it releases after them.
  yantra's `dist/` is untracked: its refold is `cyrius distlib` at the tag.

## Potential backlog — 6.x-cycle, unscheduled (NOT parked to 7.x)

> Items are ADDED here during the feature releases, with a repro; only the user promotes one into a release.
> Re-triaged 2026-10-08 against the 6.7.6 open's premise-check: what shipped is gone — its record is the CHANGELOG.
> Placed later-minor work (the DCE compaction arc, `net.cyr` §4, AF_UNIX, the syscall families) is in
> [roadmap_6.md](roadmap_6.md).

**Compiler — language and codegen**
- **Assigning a pair-returning call to an existing single variable keeps only the tag, silently** (found 2026-10-08,
  `build/cycc` 6.7.6): `var t, v = f(5); var rt = 0; rt = f(7); return rt;` with `fn f(x) { return ret2(0, x); }`
  exits 0 with no diagnostic. The single-bind refusal covers `var x = f()` (in a fn since v6.5.67, top level since
  6.7.6) but not a plain assignment; and there is no `t, v = f();` re-assignment form (`expected '=', got ','`), so a
  loop that re-polls a `Result` must bind a fresh pair each iteration. Refusing the assignment changes what compiles,
  and a re-assignment form is new syntax — both the user's call.
- `x += 1.5` on an integer slot is silent while `x = x + 1.5` warns ("integer arithmetic with an f64 right
  operand"): `_asg_compound_op`'s integer arm has no kind-2 check, so `h.n += 1.5` is silent too. One warn in the
  shared helper.
- "the result is a temporary" is false for a pointer return: `gp().n = 5` with `fn gp(): *H` is refused
  (`_stmt_call_field`, parse_expr.cyr). Whether a field of a returned pointer is an lvalue is a language question.
- A fn whose body ends in `loop { … }` or `do … while` is not "provably returning" to pass 1
  (`_body_ends_in_return` reads a final `do` as a `while`): GFLG bit 1024 stays clear, so a `var a, b = f()` refusal
  is missed for such an `f` — conservative.
- A variable or subscript for-step never checks its `)` (`for (i = 0; i < 3; i += 1 2)` builds); field and `*p` steps
  do since 6.7.5.
- A captured 8-byte pointer-mode struct local is copied into the closure env while a 16-byte one is captured by
  reference (`_CL_CAP_BASE_RA`'s rule); `=` and `OP=` agree.
- cx: a fn returning a 16-byte struct is refused ("int-class 16B struct pair-return ABI not supported"), so
  `crossos/for_step_struct_assign.tcyr` does not build for cx.
- Struct-operator results (found by 6.7.6 lane E2; repros `~/.cache/c6/b1f_E2/p/`): an untyped `var r = mk3(4) - s;`
  is typed `P3` although `P3_sub` returns an integer; after an integer `-` whose right side is a struct the result
  keeps the struct's type (`n - s + 10` dispatches `P3_add` and crashes); `-s + t` ignores the minus;
  `return (a, b);` in a struct-returning fn takes the multi-value path and the caller reads garbage over 16 B;
  `return mk2(1) == p;` in a 9–16 B struct fn leaves the second register unwritten (closing it refuses code that
  compiles today — the user's call); a write to a captured NAME inside a closure says "undefined variable".
- A struct-typed FIELD as the LEFT operand of an overloaded operator passes the containing struct's address
  (`h.p - s` → -8, want -6); the right operand is right.
- A parenthesised argument to a ≤ 8 B by-value struct parameter skips the 6.7.3 type check (`bs1((t))` compiles,
  `bs1(t)` is refused — `_sarg_byval_small` returns before the 6.7.6 unwrap).
- u128 beyond `+` / `-` / comparisons: a `v: u128` parameter is an 8-byte slot holding the low word (`&v + 8` reads a
  neighbour); a `: u128` return type and u128 struct fields are refused; a u128 captured by a closure reads as the
  address of its env copy (parse_expr.cyr ~2697).
- A call through a variable / closure returning f64 gives an untyped word (the return type cannot be known; documented
  in the guide).
- `*p = v` through `p: *f32` / `*i32` is a raw 8-byte word store (documented — outside "every f32 write rounds").
- `CYRIUS_IR=3` (opt-in): a SIGNED narrow field through a pointer or a closure capture reads garbage (the
  negative-width EFIELD_LOAD_W is not IR_RAW_EMIT-recorded; 6.6.12 fixed only `_arr_sub_load`); and
  `struct HS { name; k; } … h.name = 40; var u = 0; u = h.name; return u + 1;` gives 8, not 41 (gate row S10).
- A top-level `var X = CONST;` stores statically AND emits a redundant run-time store; `2 * CONST` in a run-time
  expression is not folded (it is in an array size or a named const).

**Diagnostics**
- TOKNAME has no names for `<=`, `>=`, `%`, `&`, `|`, `^`, `<<`, `>>`, so "expected '=', got unknown".
- A field store in a const fn body reports "expected ';', got '.'"; `C.x = ..` on a const reports "no struct type in
  scope for 'C'" — neither names the real refusal.
- `--syntax-only` (`cyrius lint`) invents "expected '=', got '.'" for `a.f.g = 1;` (and `+=`) when `f: *Foo` and `Foo`
  is declared in another file (the v6.5.19 false-accusation class).
- Low: a const fn's scope error is reported twice; an unclosed call argument list followed by a loop cascades three
  errors; a method-call for-step cascades "undefined function"; a missing `}` at EOF with two blocks open prints its
  second error at `0:1` with no file.

**Bootstrap — cybs and the seed (the trusted root)**
- cybs compiles a call to an UNDEFINED function in statement position silently (`nosuch(1);` → the program segfaults);
  the expression form errors. Refusing it needs a check that gen1 carries no unresolved fixups and probably new labels
  — the trusted root's first rung, so it is placed, not slipped in.
- cybs reports a bare "syntax error" with no file or line for syntax it does not support (`const`, `loop`, `do`,
  if-expressions, unary minus, `>>>`, `>>=`).
- The seed (`bootstrap/asm`) silently truncates its input at 131,072 bytes, has a 512-entry label table with no bounds
  check, and stores into CODE (S+0x20000, 65,536 B) unbounded. Gate row S of `cybs_call_arity_named.sh` guards
  `cybs.cyr`'s headroom; a real fix is a new seed binary — a new trusted root, the user's call.

**Tooling**
- ⚠ **`cyrius distlib`'s owner rule credits a fold monolith by directory order — check.sh is RED whenever `TMPDIR` is on
  tmpfs** (found 2026-10-08; reproduced on a pristine `git archive` of HEAD at 6.7.6): with `TMPDIR` unset (`/tmp` is
  tmpfs here, which lists newest-first) `tests/gates/toolchain/distlib_sidecar_host_independent.sh` fails axis 3 every
  run — `[zzz_mono sysz]`: the PE-only `EINTRZ` is credited to `zzz_mono`, the first declarer in directory order,
  although the monoliths carry a fold header and the rule says a fold bundle is never the owner while a non-fold file
  (the `sysz_linux` / `sysz_macos` peers) declares the name. With `TMPDIR` on this box's ext4 it passes 3 of 3 (hash order; the
  fixture gives a first-declarer regression only 3-in-5 odds of showing on ext4) — which is how the 6.7.6 release gate
  read GREEN. Host-dependent sidecars are exactly what the
  gate exists to stop.
- Six hand-kept copies of the lexer's attribute-word list (cyrlint, cyrfmt, cyrdoc, cbt/srcscan, api-surface,
  cyaudit); only cyaudit's is held to LEXATTRWORD by a census. Move LEXATTRWORD into an includable pure file (measured
  byte-identical on all seven forks) or give each tool the census.
- CLI leftovers (6.7.6 review): on Windows `_abs_path` is the identity (the PE CLI warns getcwd / brk unrouted), so an
  absolute in-project path counts as outside the project for `test.cyml` and `CYRIUS_TEST_FILE` / `DIR` are relative;
  a symlinked working directory spelled with the logical `$PWD` does not match the physical one; `_abs_path(".")`
  returns `<cwd>/.`; `_process_named_deps` reports one error per manifest walk ("1 errors" for two);
  `cyrius lib sync --dry-run` prints `would sync: <integer>` (`cbt/commands.cyr` ~1796); `cyrius update` copies the
  whole pinned stdlib snapshot into `lib/` whatever `[deps] stdlib` declares; `_dep_local_state`'s
  GIT_CEILING_DIRECTORIES is not normalised; under wine the PE CLI cannot hash (no certutil), so it writes no lock.
- Test tooling: `cmd_test` labels any exit status above 128 a signal (a test exiting 232 prints "killed by signal
  104"); `cyrius bench` / `cyrius fuzz` exit 0 when they find nothing; a `[test.embed]` name duplicating `[embed]`'s
  says "declared twice" without naming `[embed]`.
- `crossos/regression_terminate_children.tcyr` is timing-sensitive on ach: it asserts a call returns under 1,000 ms and
  a 600 ms deadline kills a background `sleep 30`; RED once in the 6.7.6 gate, then 11/11. Widen the bounds or measure
  against a calibrated clock.
- Named manifest profiles (`[build.PROFILE]`, P1's deferred half) and `[build] target` (recognised and warned since
  6.6.17, not read).
- `gates_never_write_tree.sh` axis 9's static wine scan cannot see a PE binary run directly through binfmt_misc.
- The two cyrlint gates, one bite: a bare-local-array slot-write lint and a `SYS_WRITE` byte-length gate (detail:
  [roadmap-future.md](roadmap-future.md) § *DX / cyrlint tooling*).

**Runtime and `lib/`**
- P6 S7, poison guard pages — the one way to catch a read that jumps a whole redzone. `mprotect`; 16 KiB pages on Apple
  arm64; `VirtualProtect` reaches no stdlib path; agnos `cyr_mprotect` is a no-op, so an agnos run must REPORT
  "unguarded".
- `tls_native_set_client_cert` sizes its decode at `TLS_CA_MAX_ROOTS` (300); sigil's `pem_count_cert_blocks` could size
  it exactly.
- TLS capability limits (CYRIUS-2026-0019's *Not covered*): no native RSA client certificates; the native client and
  server send their leaf only; an empty certificate_authorities; the 1.3 server reads each client message from one
  record (a client Certificate of at most 8 KiB). Not taken so far: a libssl-backend `tls_set_groups`; X448 /
  secp521r1 (sigil has neither ECDH).
- Windows `sys_symlink` widens at 519 units with no `\\?\`, so a link path over 260 units fails -1 (honest).
- The unused `SYS_ACCEPT4 = 288` in `lib/syscalls_macos.cyr` (cosmetic: `sys_accept4` is composed from accept + fcntl).
- Literal bounds left in `lib/` (6.7.6 lane H): the agnos env blob `1024` in `_agp_env_vec` / `_rga_env` /
  `_async_agnos_run`; `lib/regex.cyr`'s `splits: i64[64]` beside a literal `sn >= 64`; `_fl_heads[72]`
  (`lib/freelist.cyr`) and `_dynlib_registry[256]` (`lib/dynlib.cyr`) take 576 / 2,048 bytes where their comments say
  72 / 256; the async ctx layouts hard-code the 40-byte kill state instead of `_PROC_KILL_STATE`; internal loops bound
  by the writable public `TLOCAL_MAX_SLOTS` / `TLS_REG_MAX`.
- `lib/hashmap_fast.cyr`: an OVERWRITE of a present key can rebuild (and double) the table — `fhm_set` checks its
  trigger before `_fhm_insert` knows the key is new (544 B at 14 live, 16 → 32 slots, and it can return -1);
  `lib/hashmap.cyr` triggers only for a NEW key since 6.6.20. When a rebuild happens is the user's to place.

**Size and platform internals**
- The x86-macOS `EMACHO_SYSXLAT` fold — XLAT-1's method on the x86 Mach-O chain (its rows are copied into every site,
  ~1.3 KB each, ~0.8 MB of the x86-macOS compiler).
- XLAT-3: arm64-macOS pipe / fork post-`svc` fixups for literal numbers (~68 B a site; verifiable on ecb only).
- `esysxlat_fold.sh` cannot see a fold that skips its `cur` update (no live re-capture row; a synthetic row in the
  gate's own probe would).
- DEAD-10: fold constant `if (SYS_OPEN == 2)` arms at parse time (6.7.2's evaluator makes it easy). HEAP-12: one
  `alloc()` arena for the IR heap bands (a two-step bootstrap).
- self_compile +6.8 % from the attribute-line rule (s-pplex `0d85cdcd`, 924 → 987 ms; likely the preprocessor half,
  `lex_pp.cyr`): take it back without reopening the forged-`#@file` vector.

**Long tail**
- DWARF debug-info emission — when a real debugger story is needed (crash localization is still x86-ELF-only).
- `tantu` — the async runtime extracted to its own repo (name reserved); a future minor, not sequenced.
- Auto-vectorization of scalar SOA loops.

## 7.x — public-release ONLY

The language book + legal (licensing / public-release prep). **No codegen, runtime or platform work ever lives at
7.x — if it compiles code, it is 6.x.**

## Open questions — standing defaults, not a queue

Each item carries its default and work starts under it; a genuine fork is asked in one line, that turn — never parked
here as "owed".

1. **The self_compile budget and the growth-tax audit — the later performance track owns both** (user, 2026-07-29;
   the audit is likely dropped, decided at that track's opening review). Input: **1,175 ms · 1,806,240 B at 6.7.6**
   (923 ms · 1,586,184 B at 6.6.19; the old ≤ 700 ms / ≤ 1.20 MB pair is exceeded on both halves — an input to
   re-decide, not a missed target). Record the outcome here.

## Standing notes — traps this minor must not re-learn

- **A batched release** runs strictly sequentially; parallelism is only INSIDE one, in git-worktree lanes where each
  file has one owning lane and every cross-lane hunk travels as a named hand-off patch to a named merge step. At most
  two `src/` lanes, one of which commits `build/cycc`; the binary is rebuilt once on the merged tree (fixpoint +
  seed-derive), `build/cycc-native-aarch64` once with `cyrius pulsar`. Ratchets and censuses (`CORPUS_FLOOR`,
  `CYCC_CEIL`, the alloc census, the cross-compile allowlist, the self-sufficiency floors) are integration steps.
  **A per-lane green is not a merged green.**
- **A ledger id (`CYRIUS-YYYY-NNNN`) is spent in the commit that records it, and only for an actual security
  vulnerability** (attacker and boundary named). That commit moves the ledger
  (`docs/audit/2026-10-08-security-ledger.md`) and state.md's next-id.
- **Text handed into a cyrius string literal obeys the 6.6.11 lexer**: a driver `_gate("…")` description carrying a
  bare `"` or an unknown escape (`\<LF>`, `\q`) stops `programs/checks` compiling.
- **A fold's CI runs isolated, never by hand-extracted steps**: a clean `git archive` copy with `path` deps commented
  out, a throwaway `CYRIUS_HOME` (a copy of the pinned slot, an EMPTY dep cache) and a throwaway `HOME`, with GitHub's
  shell semantics (`bash -e` unless the workflow says `shell: bash`).
- **The `PARSE_RETURN` tail path has skipped a call-site obligation five times** (v6.3.36, v6.4.53, v6.5.1, v6.5.2,
  and `defer` at 6.6.7). The diverts are one predicate now (`_tc_must_divert`, parse_fn.cyr), so a new obligation is a
  new line THERE; grep the tail path for the SHAPE of any new `PARSE_FNCALL`-resident transformation.
  `EDEFER_SAVE` / `EDEFER_RESTORE` must preserve every return register of every return convention (x86: rax, rdx, r8,
  xmm0, xmm1; aarch64: x0–x3, q0, q1; cx: r0–r5) — a new return class that adds a register adds it there.
- **A filing's target list is a report about what the reporter builds, not about the bug.** Reproduce on every host
  that shares the path before scoping the fix (the v6.6.1 DCE issue said "PE only" while x86 Mach-O crashed on ach).
- **An all-identical codegen differential is evidence of a corpus blind spot**, not that a fix is inert: when a fix
  measures 0 diffs, add the shape to the corpus in the same release.
- **A "found by ports" test beats the gate that says the code compiles**: whenever a slot adds a platform-facing verb,
  the `tests/tcyr/crossos/` file is the deliverable.
- **A gate fixture in the wrong order is a vacuous gate**, and a fixture that shares the implementation's assumption
  proves nothing: mutation-prove the gate and check the mutation is reachable.
- **The FREED compiler-state scalar holes are a policy, not a work item**: the next new compiler-state scalar goes into
  a hole (`grep -n FREED src/main.cyr`), not a new slot in the band.
- **Re-derive every count in this file at each release** — a number in a roadmap has nothing checking it.
