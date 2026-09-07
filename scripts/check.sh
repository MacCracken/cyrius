#!/bin/sh
# scripts/check.sh — thin shim around programs/checks/main.cyr.
#
# v5.9.1 (2026-05-06) — first slot of the v5.9.x sovereignty pass
# (bash-toolchain → cyrius). The dispatcher logic that used to live
# here (~743 LOC of bash) moved into cyrius. At v6.0.90 the monolithic
# programs/check.cyr (10.2K LoC) was split into programs/checks/
# (slim dispatcher main.cyr + per-suite files). This shim:
#   1. cd's to the repo root so child gates see the expected CWD,
#   2. builds build/cyrius_check on demand (mirrors the v5.8.44
#      auto-build pattern for build/cyrius_api_surface),
#   3. exec's the binary, propagating its exit code.
#
# scripts/lib/audit-walk.sh stays bash for the v5.9.x window — it
# is still consumed by the bash scripts/cyrius dispatcher, queued
# for cyrius conversion at v5.9.5 alongside that dispatcher. The
# fmt/lint walk logic was simultaneously ported into
# lib/audit_walk.cyr (cyrius stdlib module) for the check program's
# use; once scripts/cyrius converts, both audit-walk.sh and this
# bridge can retire together.

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CHECK_BIN="$ROOT/build/cyrius_check"
# v6.0.90: programs/check.cyr split into programs/checks/ (slim dispatcher
# main.cyr + per-suite files). CHECK_SRC is the dispatcher; the rebuild
# trigger watches EVERY suite file (a single-file -nt test would miss a
# stale binary after a suite edit — masking a regression).
CHECK_SRC="$ROOT/programs/checks/main.cyr"
CC="$ROOT/build/cycc"

# ⛔ v6.5.42: watch the INCLUDED lib files too, not just programs/checks/*.cyr. The suite
# includes lib/audit_walk.cyr (and others), so a change there produced NO rebuild and the run
# silently exercised a stale binary — measured: a fix to the audit walkers appeared to have no
# effect at all, and the wrong conclusion was nearly drawn from it. Same failure family as the
# swallowed compile error below: the suite must not be able to run against source it was not
# built from.
NEWEST_SRC="$(ls -t "$ROOT"/programs/checks/*.cyr "$ROOT"/lib/audit_walk.cyr 2>/dev/null | head -1)"
# Rebuild if: no binary, the glob matched nothing (force a rebuild so the
# build fails loudly rather than running a stale binary), or any suite file
# is newer than the binary.
if [ ! -x "$CHECK_BIN" ] || [ -z "$NEWEST_SRC" ] || [ "$NEWEST_SRC" -nt "$CHECK_BIN" ]; then
    if [ ! -x "$CC" ]; then
        printf "error: build/cycc missing — run 'sh bootstrap/bootstrap.sh' first.\n" >&2
        exit 1
    fi
    # ⛔ v6.5.40: FAIL LOUDLY. This was `> "$CHECK_BIN" 2>/dev/null` with no status check, so a
    # compile error in the suite was invisible AND left a truncated $CHECK_BIN that was then
    # chmod +x'd and run — producing either no output at all or a stale-looking result with no
    # hint that the suite never built. Cost real time during v6.5.40 (an undefined helper in a
    # debug edit produced a completely silent run). The compiler's own diagnostics are the
    # thing you need here, so they are shown.
    if ! cat "$CHECK_SRC" | "$CC" > "$CHECK_BIN" 2>"$CHECK_BIN.err"; then
        printf "error: the check suite failed to compile:\n" >&2
        cat "$CHECK_BIN.err" >&2
        rm -f "$CHECK_BIN" "$CHECK_BIN.err"
        exit 1
    fi
    rm -f "$CHECK_BIN.err"
    chmod +x "$CHECK_BIN"
fi

# Run the cyrius gate suite. On a targeted run (a suite name was passed),
# exec it directly — the bare-metal boot gate is a full-run-only capstone.
if [ $# -gt 0 ]; then
    exec "$CHECK_BIN" "$@"
fi
"$CHECK_BIN"

# v6.2.28 D7: the bare-metal kernel BOOT gate — a real QEMU execution of the
# kernel built via the formalized triple. This anti-rots the v6.2.27 kernel
# codegen the way the macho port never was (a green checkmark is not
# verification; the kernel actually running IS). Visibly skips when qemu is
# absent rather than masquerading as green.
sh "$ROOT/scripts/qemu-boot-gate.sh"

# v6.4.47 (arc #3): UEFI Authenticode signing end-to-end gate — `cyrius sign-efi`
# signs a synthetic PE and an independent oracle (openssl + from-scratch PE-hash)
# confirms the signature is one a real UEFI firmware would accept. Skips if openssl
# is absent. The sign path is lib/CLI-only (cycc byte-identical), so this is the
# behavioral gate for the signer.
sh "$ROOT/scripts/sign-efi-gate.sh"

# v6.4.81: value-form SIMD must exist on every EMIT path, not just the native
# forks. main.cyr's PE/Mach-O CROSS arms were missing CYRIUS_HAS_VAL_SIMD_PARAMS
# since v6.4.31, so the same source built differently depending on WHERE it was
# built. Host-side by necessity: a tcyr runs natively on each host and therefore
# exercises main_win.cyr (always correct), never the cross path.
sh "$ROOT/tests/gates/platform/valform_simd_crosstarget.sh"

# v6.5.0 Phase 1 (public/private visibility): every fn must be attributed to the
# source file its `fn` keyword is in. Phase 2 turns that partition into a visibility
# boundary, so a wrong stamp means `private` silently mis-scopes. Gated here at
# Phase 1 — while the table is still recorded-not-enforced — so the substrate is
# never write-only and never unverified.
sh "$ROOT/tests/gates/frontend/fileid_substrate.sh"

# v6.5.0 Phase 2: file-scoped `private` / per-item `public`, WARN mode. Asserts
# per-RESOLUTION-PATH (ordinary / tail / operator), because enforcement that covers
# only the obvious path is the v6.4.81 `_cfo` shape repeating — that class was
# declared fixed three times before the fourth occurrence turned up in a path nobody
# had enumerated.
sh "$ROOT/tests/gates/frontend/visibility_private.sh"

# v6.5.1: overload-suffix dispatch must be ARITY-AWARE and POSITION-CONSISTENT.
# Asserts across assign / return-tail / nested-arg because the two defects it covers
# were *position-specific* — the redirect ignored the target's arity on the assign and
# nested paths, and PARSE_RETURN's tail path skipped the dispatch entirely, so the same
# call spelled two ways ran two different functions. The 253-file corpus changes 0 bytes
# under the arity fix, i.e. it had ZERO coverage of the shape, which is why this must be
# a gate and not a .tcyr.
sh "$ROOT/tests/gates/frontend/overload_arity_dispatch.sh"

# v6.5.1: the agnos O_RDWR flag-map gate (v6.4.27) was CI-ONLY — `ci.yml` ran it and
# nothing local did, so `release-gate.sh` could report GREEN while CI went RED. It did
# exactly that this release: the arity escalation above turned the gate's `sys_unlink(path)`
# into a hard error (agnos's wrapper is length-carrying and takes 2 args), and the local
# gate never noticed. A gate CI runs but the release gate does not is the same blind spot
# as grading check.sh by its stdout instead of its exit status — fixed the same way, by
# making the local gate actually run it. `tests/gates/memory/heapmap.sh` is the only other CI-only
# script and it is genuinely redundant: `_heapmap_gate()` in the check binary covers it.
sh "$ROOT/tests/gates/platform/io_rdwr_agnos.sh"
# v6.5.54: the NOP-harvest compactor must run under IR mode, and the resulting compiler
# must WORK. It was gated off for every IR mode, so CYRIUS_IR=3 shipped 19,067 NOP
# instructions against the default path's 44 (+65,320 B of .text). The gate could not
# simply be lifted: the compactor moves code and the IR records a code position per node,
# so without the stage-3c CP repair the IR-built cycc dies at startup with
# `alloc_init: mmap failed` — mutation-proven, and that reproduction check, not the NOP
# count, is what this gate is really asserting.
sh "$ROOT/tests/gates/codegen/ir_nop_harvest.sh"

# v6.5.54: ir_build_edges must resolve jump targets within a function. Both BB finders
# scanned the whole program per jump (one of them nesting a node scan inside that), which
# put CYRIUS_IR=3 at 13,967 ms against 672 ms — 21x, and ALL of it here: with FOLD, LASE,
# DCE and DSE all disabled it was still 13,910 ms. Pins the COST, not the mechanism, so any
# sub-quadratic scheme passes.
sh "$ROOT/tests/gates/codegen/ir_edges_scaling.sh"

# v6.5.55: `enum N: stack` must construct payload variants with NO allocation, the plain boxed
# form must be untouched, and a variant too wide for the (tag, payload) pair must be REJECTED
# rather than silently truncated. Axis 3 is the point: v6.5.15 already tried to stop boxing, by
# relocating the box to a per-call-site global, and shipped a compiler that reported a failed
# file open as SUCCESS in a retaining loop while passing every gate of its day. This gate builds
# N values at ONE call site, keeps them all live, and checks each — and pairs every zero-growth
# assertion with a non-zero control so it cannot go vacuous.
sh "$ROOT/tests/gates/codegen/stack_enum_no_alloc.sh"

# v6.5.56 P0: identifier dedup must be an EXACT compare. It was a PREFIX compare that happened to
# be exact only while `bucket = klen` put one length per chain; v6.5.50's content hash removed
# that invariant without adding the terminator check it had been standing in for, so a shorter
# identifier took a longer one's pool offset and the two became ONE symbol
# (`var ah = 7; var ahxaa = 99;` read `ah` as 99, exit 0). 127 repos carry a colliding pair.
# ⛔ The self-host fixpoint CANNOT see this — cycc's own source has 0 colliding pairs of 54,089,
# and the mutation proof confirms a deliberately-broken compiler still reproduces itself
# byte-identically. This gate pins the PROPERTY on known-colliding pairs instead.
sh "$ROOT/tests/gates/frontend/lexid_prefix_exact.sh"

# v6.5.56: `private fn h()` must be rejected rather than silently privatising the whole file
# (twelve releases live, no diagnostic). Axes 2-3 keep the fix honest: the own-line and
# `private;` forms are the legitimate spellings and must keep working.
sh "$ROOT/tests/gates/frontend/private_per_item_rejected.sh"

# v6.5.57: copying an aggregate must copy EVERY word. `dst = src;` used to copy only the first
# 8 bytes for structs AND vectors — reported as a SIMD bug, but a two-field struct truncated
# identically. Axis 7 keeps THREE aggregates live because the fix also had to close a latent
# register-allocator bug: an aggregate's fields are reached as `lea rcx,[rbp+base]`, so only its
# base slot ever appears as an rbp disp and the picker could promote a later word whose real
# writes go through rcx. With only two aggregates the picker never reaches its `count > 1`
# threshold and a build with that exclusion removed still passes.
sh "$ROOT/tests/gates/codegen/aggregate_copy_all_words.sh"

# v6.5.58: the SIMD-param inline predicate must SEE a wide parameter whatever its width.
# `_fn_has_simd_param` scanned slots [0, pc), but a wide param's SLTYPE lives on its NAMED slot,
# after (slots-1) anonymous fillers — so the window contained it only for TWO 128-bit params.
# Single-128-bit and ALL 256-bit params were invisible and never inlined. Axis 2 is the control:
# an i64-param fn must still be called, because general inlining is default-off for a measured
# reason and this predicate exists to admit the SIMD wrappers WITHOUT switching it on.
sh "$ROOT/tests/gates/codegen/simd_param_inline_reach.sh"

# v6.5.59: an INLINED 256-bit return must carry all four lanes. The replay re-parses the callee
# inside the CALLER's function context, so `return r;` emitted the caller's return convention —
# which moves ONE XMM. A 256-bit return is a PAIR, so lanes 2-3 were left stale, exit 0, no
# diagnostic. ⭐ Every lane is asserted: a lane-0 check passes while half the vector is wrong,
# which is why no existing SIMD test caught it.
sh "$ROOT/tests/gates/codegen/inline_simd256_return_lanes.sh"

# v6.5.60, REWRITTEN v6.5.62: the fixed-lane SIMD wrappers must not pay a per-call AVX2 dispatch,
# and the ymm kernel must keep its advantage where that advantage is real. ⛔ This gate's axis 2
# used to REQUIRE the per-call gate by grep, i.e. it asserted the opposite of the truth — it would
# have gone red on the correct change and stayed green through the wrong one, and never had a
# chance at the +59 % that shipped at v6.5.24. Measured one variable at a time: the dispatch CALL
# was the whole cost (~25 %); ymm at a fixed 4 lanes is free. Axes now measure behaviour.
sh "$ROOT/tests/gates/codegen/simd_valueform_no_avx_transition.sh"

# v6.5.63: `#inline` must actually inline, must WARN when it cannot, and must not change results.
# The directive had NO handler anywhere in src/ until now — it lexed as a comment and did nothing,
# silently, while consumers wrote it (svara has four markers in src/formant.cyr, and its own
# src/lod.cyr records measuring one at "+0.7% -- noise": a measurement of an optimisation that was
# not there). ⭐ The failure mode is a quiet revert to doing nothing, which a results-only test
# cannot see, so axis 1 counts call sites and axis 2 pins the diagnostic. Mutation-proven: arming
# nothing gives "with=100 without=100" and axis 1 fires.
sh "$ROOT/tests/gates/codegen/inline_directive.sh"

# v6.5.64: a fixed-lane vector op on three &local operands must emit the DIRECT form (two rbp
# loads, the packed op, one store) with its result reload ELIDED by SLASE — while a real batch
# keeps its pointer+loop kernel and stays correct. ⛔ The instruction saving is NOT the point and
# was measured worth ZERO on its own (a replica removing exactly that scaffolding ran 33.99 ms vs
# 33.96 ms); the win is the removed store-to-load forward, which is why axis 2 asserts the elided
# reload rather than a short instruction stream. Axis 3 is the anti-vacuous control: the fast path
# is chosen by token lookahead, so a loosened precondition would emit a 16-byte op over a real
# batch's extent.
sh "$ROOT/tests/gates/codegen/simd_direct_form.sh"

# v6.5.67: a `: stack` enum value is TWO registers (rax=tag, rdx=payload). Consuming it where only
# one survives must be a hard ERROR. v6.5.55 shipped the representation with nothing recording
# which calls produce a pair, so the idiomatic forwarding shape silently kept the tag and dropped
# the payload — measured p==9 (a stale rdx) where 3 was correct, exit 0, allocator delta 0, i.e.
# the v6.5.15 "failure reported as success" class on the payload. `?` was worse: rc=0 then SIGSEGV,
# because it dereferences the tag. ⭐ Axis 6 is the anti-vacuous control — a BOXED Result must be
# entirely unaffected, or the check would refuse the documented idiom at ~1,864 ecosystem sites.
sh "$ROOT/tests/gates/frontend/stack_enum_lossy_context.sh"

# v6.5.68: cycc's x86 LENGTH DECODER must be able to walk every function body cycc emits.
# `DECODE_LEN` feeds `RA_SCAN_LOOPS`, which finds the backward edges that drive v6.5.35's
# loop-aware live-interval extension in the register allocator — on the DEFAULT path — and
# nothing had ever verified it against the bytes cyrius actually emits. Two gaps: `0x99`
# (CQO, emitted before EVERY integer division) had no case, so the picker fell back to
# whole-function intervals in every function using `/` or `%`; and the whole `0F`+imm8-after-
# ModR/M class (`0F BA` BT-group, `0F 70`-`73` shift groups, `0F C2`/`C4`/`C5`/`C6`) returned
# a length ONE BYTE SHORT. ⭐ The second is why this gate walks code instead of checking a
# size: an incomplete decoder returns 0 and callers fall back safely, but a WRONG length
# desynchronises the walk over a real backward edge — and the reverted-fix mutant is byte-for-
# byte the SAME SIZE as the correct compiler, so no size or NOP-count assertion can see it.
sh "$ROOT/tests/gates/codegen/decode_len_coverage.sh"

# v6.5.68: the NOP runs the IR passes write AFTER every per-function compaction has already
# run are collected by a whole-program pass, and the COMPACTED compiler must be a working one
# that emits exactly the bytes the uncompacted one does. ⭐ The byte count only proves the
# pass ran; axis 2 — compile with the compacted compiler and compare — is the assertion that
# matters, because moving code invalidates every stored code position and ONE unrepaired
# table is a silent miscompile. v6.5.54 demonstrated exactly that by lifting the per-fn pass's
# IR gate without repairing `IR_NODE_CP`, producing a cycc that died with
# `alloc_init: mmap failed`. Seven tables are repaired here, including the entry trampoline's
# hand-emitted disp32, which no emitter registers at all.
sh "$ROOT/tests/gates/codegen/wholeprogram_nop_compaction.sh"

# v6.5.69: an `async fn` that awaits MID-BODY suspends and resumes where it left off. Before
# this, `await` lowered to a synchronous `future_force` call and a parked task re-entered its
# body FROM THE TOP — so the natural shape compiled clean and did nothing (a TTY relay written
# that way relays ZERO bytes and hangs). ⭐ Axis 1 asserts a side-effect TRACE, not a value:
# the arithmetic still lands on the right number under restart-from-top, so a value assertion
# passes on a compiler with no transform at all. Axis 2/3 are the anti-vacuous pair — an
# `async fn` with no mid-body await must compile to BIT-IDENTICAL bytes, which is why the
# transform is selected by the body rather than by the keyword.
sh "$ROOT/tests/gates/frontend/coroutine_midbody_suspend.sh"

# v6.5.71: `#derive(accessors)` getters/setters reach the inline-replay path — a measured 3.45x
# on the accessor shape, for generated code nobody hand-tunes. ⛔ Axis 2 is the load-bearing
# anti-regression: the obvious implementation (emit `#inline` into the generated text) CANNOT
# work, because derive bodies are flattened onto ONE LINE for line-number fidelity and `#` opens
# a COMMENT — so the `#` swallows the rest of that line including the NEXT `#derive`. The request
# therefore travels beside the text as a recorded name hash. Axis 1 counts CALLS, not values: an
# inlining change is invisible to a result assertion (mutation-proven — disabling the side
# channel leaves every answer correct and moves callq 3 -> 7).
sh "$ROOT/tests/gates/frontend/derive_accessors_inlined.sh"

# v6.5.72: `CYRIUS_DCE=1` REMOVES dead code instead of padding it — the flag found unreachable
# functions, overwrote them with 0x90 and reclaimed ZERO bytes while telling users to "set
# CYRIUS_DCE=1 to eliminate". ⭐ Axis 2 is load-bearing: moving code invalidates every stored
# code position, and one unrepaired table is a silent miscompile — this took four attempts and
# six distinct causes, the last being ftype-3 fixups (absolute function addresses behind
# indirect calls), which no body-level check can see because every body still decodes. A byte
# count proves the pass ran; only compiling WITH the result proves it was repaired.
sh "$ROOT/tests/gates/codegen/dce_eliminates.sh"


# v6.5.2: every folded stdlib that builds for Linux must also build for agnos.
# `lib/yukti.cyr` shipped SIX agnos ABI errors for months — including `sys_mount` called
# with 5 args against agnos's 0-parameter no-op stub, so yukti returned Ok() for a mount
# that never happened — because NO gate had ever compiled a folded stdlib for a non-Linux
# target. Parity (Linux-OK-but-agnos-broken) rather than "must build", since the distlib
# bundles deliberately do not carry their own stdlib deps. Reports its own coverage: 11/12
# today, niyama skipped and named.
sh "$ROOT/tests/gates/platform/folds_agnos_parity.sh"

# v6.5.2: ir_const_fold must not erase a following jump. EJCC/EJMP0 were the only two
# x86 emitters that recorded their IR node AFTER emitting bytes, so the node's CP was the
# END of the jump; const_fold's NOP-fill span (CP(ni+1) - CP(ni_a)) then ran 5-6 bytes long
# and swallowed it, and `return <const>;` fell through. CYRIUS_IR=3-only, so the default
# corpus was 0/253 unaffected and could never have caught it. Capstone assertion is that
# IR=3 self-hosts a byte-identical cycc — the strongest semantics-preserving statement
# available on the largest program in the tree.
sh "$ROOT/tests/gates/ir-opt/ir3_fold_jump_span.sh"

# v6.5.3: a diagnostic's LINE must survive include expansion. Main-source errors used to
# report `actual - includes_before_it` (line 2 said 1; two includes still said 1). Ten
# shapes, incl. include-once skips and a NESTED include — mutation-proven: 8 of 10 fail on
# the 6.5.2 binary, and the 2 that pass are the regression guards.
sh "$ROOT/tests/gates/diagnostics/diag_line_after_include.sh"

# v6.5.34: `#@pkgver`'s "is the constant referenced?" scan ran on the ENTRY FILE's raw text,
# before includes expanded — so CYRIUS_PKG_VERSION resolved from the entry file and failed
# from an included one, the reverse of what a byte-0 marker implies. Filed by agnostic. The
# scan moved to the tail of PP_PASS, where the unit is expanded; the declaration is emitted
# optimistically at the top and BLANKED TO SPACES if unused, so the binary of a program that
# never asked for the feature is unchanged (auto_deps_verb_gate axis 5) and no line moves.
sh "$ROOT/tests/gates/frontend/pkgver_visible_in_includes.sh"

# v6.5.5: an IR_RAW_EMIT marker only shields raw bytes until the NEXT RECORDED node.
# ESWITCH_DISPATCH_PRE recorded one marker at the top, then emitted four recorded nodes
# (EPUSHR/EMOVI/EMOVCA/EPOPR) BEFORE its raw `sub rax, rcx` / `cmp rax, rcx` — so those
# raw bytes had no node and DCE could not see they READ RCX. It eliminated the MOV_CA
# feeding them and the switch dispatched on a stale rcx. Filed against cyrius-doom as a
# LASE bug; it is DCE (CYRIUS_LASE_OFF disables the shared NOP-filler for all three
# passes, which is why the bisection pointed at LASE). CYRIUS_IR=3-only — markers emit no
# bytes, so default codegen is byte-identical and the default corpus could never see it.
sh "$ROOT/tests/gates/ir-opt/ir3_switch_dce.sh"

# v6.5.34: the three remaining CYRIUS_IR=3 divergences, one per pass — LASE eliminating a
# load whose width conversion IS the semantics, const_fold pairing operands across the NOPs
# it wrote itself, and ESTOC (`mov [rcx], rax`, the struct field store) recording no IR node
# so DCE killed the `mov rcx, rax` addressing it. That last one is the SECOND occurrence of
# the class the ir3_switch_dce gate above documents: bytes emitted with no node are bytes
# liveness cannot see. All three are IR=3-only, so all 282 corpus files passed throughout.
# With this, default-vs-IR=3 is at ZERO divergences across the whole corpus.
sh "$ROOT/tests/gates/ir-opt/ir3_substrate_correctness.sh"

# v6.5.35: the linear-scan register allocator finally USES the intervals it has computed
# since v5.6.19. Two things blocked it, and the roadmap's "it is one line" framing named only
# the first: every interval's end was force-set to the fn end (a DELIBERATE v5.6.22 guard —
# naive time-sharing miscompiles across a backward edge; measured, it fails 69 of 282), and
# `picked` was a LIFETIME cap of 5 that blocked assignment however many registers expire had
# freed. Loop-aware extension via RA_SCAN_LOOPS replaces the blanket guard; the lifetime cap
# now applies only when the bisection knob asks. -8.5% frame accesses on consumer programs.
sh "$ROOT/tests/gates/ir-opt/regalloc_cross_bb.sh"

# ⛔ v6.6.0 — THE AGNOS CROSS-BUILD GATE, MOVED FROM CI-ONLY TO HERE, AND THE REASON MATTERS.
# This gate compiles ten CYRIUS_TARGET_AGNOS fixtures (net/entropy/clock/TLS #45-#55, the
# server-socket peer #56/#57, fs dir-listing, sync, io locks, signals, the GPU band, agnoshi).
# It lived ONLY in `.github/workflows/ci.yml`, so `release-gate.sh` — the thing CLAUDE.md calls
# the single consolidated pre-tag check — was structurally blind to it.
#
# ⚠ THAT BLINDNESS SHIPPED A RED CI AT v6.6.0. The Result value-form flip changed the arity of
# every Result, and three of this gate's fixtures are heredoc'd cyrius programs using the old
# boxed idiom (`var sr = tcp_socket(); ... payload(sr)`). The repo-wide migration swept `lib/`,
# `src/`, `tests/`, `programs/`, `benches/` and `cbt/` — every place cyrius CODE lives — and
# missed fixtures embedded in `scripts/`. The full release gate went GREEN (240/240, four hosts)
# and CI still failed, which is the inverse of the macOS-rot lesson and just as bad: there, a CI
# job that never ran the compiler hid a break for nine minors; here, a gate that ran ONLY in CI
# meant the local authority could not see one. A gate the release gate cannot run is not a gate
# the release gate can vouch for.
#
# ⚖️ THE OTHER THREE CI-ONLY SCRIPTS STAY IN CI, and that is a decision, not an oversight.
# `funcgate-stage.sh` / `funcgate-posix.sh` STAGE AN INSTALL into $CYRIUS_HOME and then drive the
# installed CLI end-to-end; running them from check.sh would rewrite the developer's live
# ~/.cyrius in the middle of a check — and this release lost the whole toolchain once already by
# treating that tree as scratch. `build-cycc-verify.sh` is a packaging verifier for the release
# tarball, not a source gate. All three were run by hand at the v6.6.0 cut and pass; the agnos
# gate is the one that both compiles cyrius source AND could regress from a language change,
# which is exactly the class that belongs in the local gate.
sh "$ROOT/scripts/agnos-crossbuild-gate.sh"
