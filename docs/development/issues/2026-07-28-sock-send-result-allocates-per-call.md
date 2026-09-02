# `sock_send` / `sock_recv` allocate their `Result` on the no-free global bump — 16 B per call on the hottest path in any server

**Status:** 🟠 **THE FILED SYMPTOM IS FIXED at v6.5.41 — the ROOT CAUSE is open and is a different size class.** Shipped: `ok_via(a, v)` / `err_via(a, e)` in `lib/result.cyr` and `sock_send_a` / `sock_recv_a` in `lib/net.cyr`, which box through a caller-supplied allocator (`arena_allocator(n)`) so a server can reset a per-request arena. Measured on a real socketpair: **100× `sock_send_a` grows the global allocator by 0 B, against 1600 B for `sock_send`** — exactly the filed 16 B/call. Layout is unchanged, so `is_ok` / `is_err_result` / `result_unwrap` / `?` accept the boxes with no change. Gate: `tests/tcyr/stdlib/result_allocator_via.tcyr` (8 assertions, every zero-growth claim PAIRED with a control that the old path still grows, so it cannot become vacuous; mutation-proven two ways).

⭐ **THE CAUSE IS NOT `Result`, AND NOT `net.cyr` — the filing flagged this as speculation and it is CONFIRMED and WIDER.** The enum payload-variant constructor lowering (`src/frontend/parse_types.cyr:386`) emits `EMOVI(S, 8 + ctor_arity * 8)` followed by a call to the function literally named `alloc` — unconditional, not allocator-parameterised. A plain user `enum Color { Red(v); Green; }` allocates the identical 16 B, and the `: Result` return annotation is a **codegen no-op** (classified as an i64-shape scalar). So this is a property of *every payload-carrying enum in the language*.

⛔ **What remains is the representation change, and it is not packable**: 24 payload-variant enum declarations across 15 files and **516** `Ok(`/`Err(`/`Some(` construction sites. ⚠ And cycc's own source cannot detect a mistake in it — every `enum` in `src/` is constants-only with no payload variants, which is exactly why an earlier attempt reached a byte-identical self-host **while being wrong**.

⚠ **Only `sock_send`/`sock_recv` got `_a` peers, and that is a drift argument, not scope.** The other seven `: Result` fns in `net.cyr` each carry `#ifdef CYRIUS_TARGET_AGNOS` branches with genuinely different semantics (AGNOS merges bind+listen, its accept is non-blocking, its connect does socket()+connect() in one). Cloning those into `_a` copies would fork per-target logic into two places that then drift. If they are ever needed, make the ONE implementation allocator-aware. ⚠ Note also that an `_a` peer **cannot delegate** to its plain twin — that allocates the global box first and re-boxes it, leaving the growth untouched. The gate mutation-tests exactly that mistake.

⚠ **FOUR CLAIMS IN THIS FILE ARE WRONG and two sit under a heading that claims to CORRECT tree facts:**
1. **"cx has no second return register / any pair-return ABI must exclude cx" is FALSE** since v6.5.21 — verified by RUNNING a pair-return program on cxvm, not by reading. This one is dangerous: an implementer scoping a pair-return design would exclude a target that works.
2. Counts are 40/107, not 39/106 (the file's own "do not quote either number" advice is right; the shape — 0 cyrius-owned — is correct).
3. The `Placement:` header contradicts the ⛔ box three lines below it and the live roadmap.
4. Line cites drifted: `net.cyr:384/:391` → `:392/:399`; `parse_fn.cyr:3135-3145` → `:3511-3580`.
`sock_send` grows `alloc_used()` by **exactly 16 bytes per call**, warm, with a zero-length
payload. The cost is the `Result` return value, not the payload. Every `Result`-returning
socket primitive in `lib/net.cyr` has the same shape.
**Re-verified against live code on cycc 6.5.10, 2026-08-07:** `sock_send` (`lib/net.cyr:384`) and
`sock_recv` (`:391`) still return bare `Ok(n)` / `Err(0 - n)`; there is **no `sock_send_a` /
`sock_recv_a`** anywhere in `lib/` and the `Result` construction is untouched. Neither v6.5.9's
growable arena nor v6.5.10's `alloc_via` call plumbing changes it — those make allocation *cheaper*
(15.1 → 11 ns) and *reclaimable when threaded*, but nothing threads an allocator through these
wrappers, so the per-call 16 B still lands on the no-free global bump.
**Placement:** **v6.5.35 — band I, Slot 9.** ⭐ **NO LONGER UNSCHEDULABLE:** take the design decision AT SLOT OPEN rather than treating it as a blocker.

> **⟳ Re-stamped 2026-08-14 at v6.5.21 (backlog re-triage).** ⭐ **THIS ITEM SHRANK.** The pair-return substrate it needed **shipped in v6.5.21** (declared multi-value returns, `fn f(): (T, T)`), dropping it from 'arc' to **1 release** and discharging the framing that made it unschedulable. Defect still reproduces byte-identical (`per call = 16`). The 9a prerequisite (~106 unannotated Ok/Err producers across five folded repos) is required ONLY under a uniform-representation design. ⛔ Do NOT record the re-triage's proposed correction text: it asserted aarch64 uses x0/x1/x3; live is **x0/x2/x3** (`src/backend/aarch64/emit.cyr:355` = `mov x2, x0`) — a wrong tree fact replacing a wrong tree fact, in the slot that has already suffered that twice.

> ### ⛔ THE COMMITTED DESIGN WAS TRIED AT v6.5.15 AND REVERTED — the placement below is stale
>
> The line under this box commits the slot to **"fix option 1 only: unbox the scalar case (tag +
> i64 payload in a register pair)"**. That was **implemented at v6.5.15, passed every gate, and
> was then refuted and reverted.** From the CHANGELOG, verbatim:
>
> > *Implemented, passed **every** gate (`delta=0`, check.sh 165/0, self-host, seed-derive,
> > 264/264), then refuted by an adversarial verifier and reverted. A per-call-site global box
> > made Results from one site share a slot, so a retaining loop reported **a failed file open
> > as success**. Both storage relocations are now disproven — frame slot too short, static too
> > shared — which settles that the fix needs escape analysis or a scope-tied arena, not
> > relocation.*
>
> **What is actually left is NOT a storage relocation of any kind.** The caller frame slot is
> too **short** (`?` inside an unannotated helper returns the box out of that helper's own
> frame — the idiomatic `Result` shape, not an edge case); static/global is too **shared** (a
> failed file open reported as SUCCESS, in the primitive whose job is reporting failure). The
> heap box buys per-value lifetime, and escaping-plus-retained values need exactly that.
>
> ⚠ This file's own later ARC-OPEN section proposes *"9b: keep it a pointer but into the
> CALLER'S FRAME via a hidden retptr per call site"* — that is the same relocation the ⛔ block
> disproved. It is **superseded, not a third option.**
>
> **Surviving designs: escape analysis, or a scope-tied arena with reclaim.** Both are a
> different size class from "unbox the scalar case into a register pair". Choosing between them
> is the maintainer's call — a design decision is a *named* file-don't-pack reason.
>
> Second consequence: the **9a prerequisite is entirely upstream.** Every unannotated `Ok`/`Err`
> producer in `lib/` lives in a **folded** module (sigil, yukti, vani, mabda, bayan) and **zero**
> are in cyrius-owned files, so 9a is a five-repo coordinated fix-at-source, not a cyrius patch.
> (Re-derived 2026-08-11: 39 fns declared `: Result` in `lib/*.cyr`. An approximate count of
> *unannotated* producers disagreed with this file's 106 — **do not quote either number**; it
> wants a real call-graph derivation at slot open.)
>
> Repro re-run unchanged at 6.5.19: `100x sock_send global-bump delta=1600  per call=16` —
> byte-for-byte identical to the 6.4.86 filing and the .10/.14 re-measurements.

**Placement (superseded — see box above):** **v6.5.x Slot 9 (`.33`–`.34`) — "Sum-type variant unboxing"** (`roadmap.md` v6.5.x
slot table, verified live 2026-08-07; *retitle at pin time*). ⭐ **The triage confirmed this file's
own "speculation" and rejected two of its three fixes:** it is the compiler's variant **lowering**,
not `net.cyr`'s use of it, so the slot takes **fix option 1 only** (unbox the scalar case — tag +
i64 payload in a register pair, no allocation). Options 2 and 3 are recorded there as traps —
arena variants push the cost onto every consumer, and a singleton silently breaks any caller
storing a `Result` past the next call, which is the trap this file itself flagged. Full ecosystem
ABI cross-walk at arc-open, one coordinated filing, not drip. Never 7.x.
**Discovered:** 2026-07-28 while closing sandhi's per-request allocations for the AgnosAI
Rust→Cyrius port (port-plan blocker #3). Found by a regression test that asserts a serve loop's
global-bump delta is flat — the test failed at 16 B/response after the sandhi-side fix was
complete, and the residual traced here.
**Severity:** Medium — no hard failure, but it is **unbounded growth in a long-running server on
a path the peer controls**, with no consumer-side workaround. Same class as the `dir_list` and
`sock_accept` filings, on a hotter path than either.
**Affects:** cyrius 6.4.86 (`lib/net.cyr` `sock_send` :384, `sock_recv` :391, and the rest of the
`Result`-returning socket surface); every earlier version with the same shape.

## ⛔ v6.5.15: IMPLEMENTED, REFUTED, REVERTED — read this before trying again

An unboxing implementation was written, passed **every gate**, and was then killed by an
adversarial verifier. It is reverted; the tree is unchanged. What it proves is a DESIGN fact,
so do not re-attempt the same shape:

**It passed:** `delta=0 percall=0` · `result_stdlib` 29/29 · `result_stdlib_pass2` 24/24 ·
self-host fixpoint byte-identical · seed-derive OK · check.sh **165/0** · full suite 264/264 ·
plus a new mutation-proven cross-OS test. Green everywhere.

**It was wrong anyway.** The box was a per-call-site anonymous **global**, so every Result from
one call site shares one slot for the life of the process. Retained across iterations:

```
3 results collected in a loop:  NEW → 3, 3, 3     OLD → 1, 2, 3
3 file_open_r, middle missing:  is_ok → 1, 1, 1   OLD → 1, 0, 1
```

**A failed file open reported as SUCCESS**, with a payload belonging to a different call — in
`lib/io.cyr`, in the primitive whose entire job is reporting failure. And two functions with
byte-identical bodies differing ONLY in the `: Result` annotation behaved differently, which is
a language soundness break, not a documented narrowing. Every gate was green because the corpus
has zero coverage of the retention shape — the v6.4.80 lesson verbatim ("251/251 byte-identical
= the corpus had ZERO coverage of the shape, not reassurance").

### ⭐ What this SETTLES about the fix

Both relocations have now been tried and both fail, for opposite reasons:
- **Caller frame slot — too SHORT.** Tried first; `result_stdlib` killed it in one run. `?`
  inside an *unannotated* helper returns the box out of that helper's own frame. That is the
  IDIOMATIC Result shape (`?`, and `if (is_err_result(r)) { return r; }`), not an edge case.
- **Static/global — too SHARED.** Above.

The heap box buys **per-value lifetime**, and escaping-plus-retained values need exactly that.
**So "unbox the scalar case" cannot be done by relocating storage at all.** A real fix needs
escape analysis, or a scope-tied arena with reclaim — a different and larger design than this
filing or the roadmap slot assumes. Retitle the slot accordingly.

### Two tree facts corrected along the way
- There are **THREE** instruction backends, not five: `backend/macho/` and `backend/pe/`
  contain no `E*` emitters — they reuse x86's.
- **cx has no second return register.** `backend/cx/emit.cyr:771,775` hard-error and the pair
  emitters at `:211,212` are `return 0;` no-ops. Any pair-return ABI must exclude cx.

## ⛔ v6.5.15 ARC-OPEN CROSS-WALK — the fix has a PREREQUISITE the filing did not know about

Premise re-confirmed on **6.5.14**: the repro is byte-for-byte unchanged (`per call=16`), three
minors running. The lowering is now read (the filing flagged its root-cause section as
speculation — it was right): `PARSE_ENUM_DEF` (`src/frontend/parse_types.cyr:333-400`) generates a
real constructor FUNCTION per payload variant which calls `alloc(8 + arity*8)`, stores tag@+0 and
payloads at +8.., and returns the pointer. So the 16 B is the box, exactly as measured.

**But the chosen fix cannot be keyed on the `: Result` annotation, because most producers do not
carry it.** Measured across `lib/`:

| | count |
|---|--:|
| fns declared `: Result` | **39** |
| fns returning `Ok()`/`Err()` with NO annotation (declared plain `i64`) | **106** |
| …of those, every return is `Ok`/`Err` (transitively inferable) | 41 |
| …of those, ALSO return something else | **65** |

The 65 are mostly not really mixed — they return `err_unknown(msg)`,
`err_invalid_argument("…")`, `err_from_syscall_ret(ret)`, i.e. *other* Result-producing helpers —
so classification needs a **transitive fixpoint over the call graph**, not a local test. But at
least one is genuinely mixed: `bayan_cyml_expand_value` returns `Ok(...)`, `0` and `val` from the
same body. Under any changed Result ABI that function is ill-typed **today**.

⚠ **Why this bites every candidate design, not just one.** Whether the unboxed form is a register
pair (the filing's option 1) or the existing hidden-retptr convention, codegen has to know at the
`return` site whether it is returning a Result. With 106 of 145 producers undeclared, it does not.
Give those a Result ABI they don't declare and they hand back a pointer into a dead frame — the
same failure shape as the tail-call escape fixed in 6.5.14.

✅ **The prerequisite is safe and cheap to verify.** `: Result` is a **no-op for codegen today**:
`parse_fn.cyr:3135-3145` (v5.10.23) explicitly classifies `Result`/`Option`/`Tagged`/`cstring` as
i64-shape scalars returning a raw pointer — "rax-via-i64 ABI not retptr-stash" — precisely so an
annotated fn does NOT silently get retptr. So annotating the 106 changes no generated code and can
land, and be gate-verified, entirely ahead of the ABI work.

**Therefore Slot 9 is two phases, and the second cannot start first:**
- **9a — normalise the producer set.** Annotate the 106, resolve the genuinely-mixed ones. Spans
  cyrius `lib/` **and the upstream repos** (sigil, mabda, bayan, yukti…) since those arrive by fold
  — fix-at-source, not in the fold. Byte-identical by construction; a gate can assert "every fn
  containing `return Ok(`/`return Err(` is declared `: Result`" and mutation-prove it.
- **9b — unbox.** Only once 9a makes the signal reliable.

### Where the 106 live — 9a is ENTIRELY upstream, none of it is cyrius's to fix

| repo (folded lib) | unannotated producers |
|---|--:|
| yukti | 49 |
| sigil | 48 |
| bayan / mabda / vani | 3 / 3 / 3 |
| **cyrius-owned `lib/*.cyr`** | **0** |

Every cyrius-owned Result producer is already declared `: Result` — including `sock_send` /
`sock_recv`, the subject of this filing. So 9a is a **five-repo coordinated upstream change**
(fix-at-source; a fix in the vendored `lib/<dep>.cyr` evaporates at the next re-vendor), which is
a named file-don't-pack reason. It is NOT a cyrius patch.

### ⭐ …which means 9b can land WITHOUT waiting for 9a, if the unboxed form stays a POINTER

The trap in a register-pair ABI is that a program includes cyrius's `lib/net.cyr` *and* the folded
`lib/sigil.cyr` in one translation unit. If annotated fns returned a pair and unannotated ones a
heap pointer, `is_ok(r)` would face two incompatible representations and break.

That disappears if the unboxed form is still **a pointer to {tag@+0, payload@+8}** — just into the
CALLER'S FRAME instead of the heap:

- annotated `: Result` fn → caller reserves a 16-byte frame slot per call site, passes it as the
  hidden retptr; callee writes tag/payload through it. **Zero allocation.**
- unannotated producer → unchanged heap box.
- **Both are pointers with identical layout**, so every consumer (`is_ok`, `result_unwrap`, `?`,
  `load64(res+8)`) works untouched, and mixed programs are correct by construction.

This makes 9b incremental and independently shippable: it takes `sock_send` to a flat bump delta —
the exact acceptance sandhi's `test_server_reject_arena_is_flat` encodes — while 9a merely widens
the win to the folded libs later.

⚠ **The one hazard to gate before shipping 9b:** a Result outliving the frame that boxed it.
Measured at 6.5.15: **0 sites** assign a `: Result` fn's output to a global in `lib/`. The
remaining shape to handle in codegen is `return <result-returning-call>(...)` — the retptr must be
threaded through, not re-boxed, or the pointer dangles. That is the same failure class as the
tail-call frame escape fixed in 6.5.14, so the guard already exists to model it (`_fn_local_addr`).

The filing's estimate ("widest win, deepest change") holds; what it missed is that the depth is in
the **consumers' declarations**, not the compiler. Roadmap slot text should be retitled accordingly.

## Summary

`sock_send` returns a `Result`. Constructing it costs a 16-byte allocation from the global bump
allocator, which has no free. The allocation is per **call**, independent of payload size, and
happens on success as well as failure.

For a CLI this is invisible. For a server it is a leak proportional to requests served: every
HTTP response is at least one `sock_send`, so an idle-but-serving process grows forever.

- 1 send/response × 10k req/s = **160 KB/s** → ~13.8 GB/day
- sandhi's chunked responses issue one `sock_send` per chunk, so streaming multiplies it

This is not a consumer bug and cannot be fixed by a consumer: the allocation is inside the
stdlib, and `Result` is the documented return type. Threading an allocator through
(`sock_send_a`) or returning a non-allocating result would both work; a consumer can do neither.

## Reproduction

```sh
mkdir -p /tmp/sockprobe/src && cd /tmp/sockprobe
cat > cyrius.cyml <<'EOF'
[package]
name = "sockprobe"
version = "0.1.0"
license = "GPL-3.0-only"
language = "cyrius"
cyrius = "6.4.86"
[build]
entry = "src/main.cyr"
output = "build/sockprobe"
[deps]
stdlib = ["syscalls", "alloc", "fmt", "io", "str", "string", "vec", "args", "assert", "result", "net"]
EOF
cat > src/main.cyr <<'EOF'
fn w(m) { syscall(1, 1, m, strlen(m)); return 0; }
fn wn(n) { var b[24]; var l = fmt_int_buf(n, &b); syscall(1, 1, &b, l); return 0; }
fn main(): i64 {
    alloc_init();
    var k = 0;
    while (k < 4) { sock_send(2, "", 0); k = k + 1; }      # warm
    var before = alloc_used();
    var i = 0;
    while (i < 100) { sock_send(2, "", 0); i = i + 1; }
    var d = alloc_used() - before;
    w("100x sock_send global-bump delta="); wn(d); w("  per call="); wn(d / 100); w("\n");
    return 0;
}
var r = main();
syscall(60, r);
EOF
cyrius lib sync && cyrius build src/main.cyr build/sockprobe && ./build/sockprobe
```

**Expected:** `delta=0` — a zero-length send to an already-open fd should not allocate.

**Actual:**

```
100x sock_send global-bump delta=1600  per call=16
```

fd 2 is used so the write itself always succeeds; the 16 B is the `Result`, not the payload.

**Re-run verbatim on cycc 6.5.10, 2026-08-07** (with `cyrius = "6.5.10"` in the manifest): byte-for-byte
the same output — `100x sock_send global-bump delta=1600  per call=16`. Unchanged in two minors.

## Root cause (speculation — flagging as such)

`Result` appears to be a heap-allocated 16-byte box (tag + payload), and `net.cyr`'s socket
wrappers construct one per call. I have not read the `Result` lowering in the compiler, so
whether the allocation is emitted by `Ok(..)`/`Err(..)` construction generally or specifically by
`net.cyr`'s wrappers is a guess. The observable per-call 16 B is what is measured.

If `Result` is boxed generally, this is much wider than `net.cyr` — every `Result`-returning
stdlib function on a hot path has it, and the fix belongs at the representation.

## Proposed fix

Ordered by how much they'd disturb:

1. **Unbox `Result` for the scalar case.** If it is a tag + i64 payload, it fits in a register
   pair and needs no allocation at all. Widest win, deepest change.
2. **Arena-aware socket variants** — `sock_send_a(a, fd, buf, len)` etc., mirroring the
   `_a` convention already used across `str.cyr` and consumer code. Consumers already thread
   per-request arenas; this would let them cover the last hop.
3. **A preallocated per-thread `Result` singleton** for the socket surface, on the grounds that
   the value is consumed immediately by the caller and never escapes. Cheapest, but it silently
   breaks any caller that stores a `Result` past the next call — probably not worth the trap.

Consumers cannot pick any of these; all three are stdlib-side.

## Consumer-side workaround

**None available.** sandhi 1.9.6 eliminated every *other* per-request global-bump allocation in
its serve loops — request buffers, response text, and refusal responses are all arena-backed and
rewound now — and this 16 B is what remains. Its regression test
(`test_server_reject_arena_is_flat`) asserts the delta over 600 responses is **exactly**
`600 × 16`, i.e. it pins this issue's cost as the known residual so that any *new* leak fails the
test. That test is the ready-made verification for a fix here: when this lands, the expected
figure becomes 0.
