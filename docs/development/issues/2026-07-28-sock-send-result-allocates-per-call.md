# `sock_send` / `sock_recv` allocate their `Result` on the no-free global bump — 16 B per call on the hottest path in any server

**Status:** 🟡 **OPEN** — measured against cyrius **6.4.86** with a standalone probe (below):
`sock_send` grows `alloc_used()` by **exactly 16 bytes per call**, warm, with a zero-length
payload. The cost is the `Result` return value, not the payload. Every `Result`-returning
socket primitive in `lib/net.cyr` has the same shape.
**Re-verified against live code on cycc 6.5.10, 2026-08-07:** `sock_send` (`lib/net.cyr:384`) and
`sock_recv` (`:391`) still return bare `Ok(n)` / `Err(0 - n)`; there is **no `sock_send_a` /
`sock_recv_a`** anywhere in `lib/` and the `Result` construction is untouched. Neither v6.5.9's
growable arena nor v6.5.10's `alloc_via` call plumbing changes it — those make allocation *cheaper*
(15.1 → 11 ns) and *reclaimable when threaded*, but nothing threads an allocator through these
wrappers, so the per-call 16 B still lands on the no-free global bump.
**Placement:** **v6.5.x Slot 9 (`.33`–`.34`) — "Sum-type variant unboxing"** (`roadmap.md` v6.5.x
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
