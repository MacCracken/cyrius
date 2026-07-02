# `str_builder` (lib/str.cyr) is not thread-safe — concurrent builders corrupt each other

> **RESOLVED — v6.3.15 (verified by this consumer 2026-07-01).** Root cause was the
> array-local codegen (a fn-scope `var X[N]` was a shared static across threads), not
> `str_builder` per se; v6.3.13 root-caused it and **v6.3.15 made array locals
> per-thread by default**. Verified on cyrius 6.3.23: the minimal repro below is now
> **`sb_fail = 0`** (was ~87%), the probe's `concurrency_repro.sh` is **0/300** (was
> ~3%), and the **multi-worker-TLS `BAD_SIGNATURE`** (the "second manifestation"
> below) is **gone** — `sandhi_server_run_pooled_tls` at `max_conns=4` serves 100/100
> concurrent HTTPS cleanly. (One narrow residual TLS issue remains at max_conns>1 —
> `RECORD_LAYER_FAILURE` under a mixed pattern — but that is a *separate*, non-str_builder
> record-layer bug, filed as `2026-07-01-multiworker-tls-record-layer-failure-under-mixed-load.md`.)

> **Status (v6.3.13): ROOT-CAUSED + fixed OPT-IN; default-on tracked separately.**
> NOT a str_builder bug at all — the real cause is that **`var arr[N]` LOCALS are
> allocated at a shared global/BSS address** (thread-shared); str_builder corrupts
> because its callers/formatting use array-locals (and the repro's own `var ch[2]`
> is thread-shared). Fixed by routing array locals to per-thread stack slots,
> shipped opt-in as `CYRIUS_STACK_ARRAYS=1` in v6.3.13. Making it **default-on** is
> blocked on SSE m128 16-byte alignment of stack slots — tracked in
> [`2026-06-30-array-locals-stack-default-on-m128-align`](2026-06-30-array-locals-stack-default-on-m128-align.md).
> The "Component" line below (blaming str_builder fns) is the original mis-diagnosis.

**Filed:** 2026-06-28 (by the `yeo-cy-test` consumer — SecureYeoman → Cyrius
full-stack viability probe; cyrius 6.3.1 wrapper / 6.3.0 pin)
**Severity:** **HIGH / blocker for concurrency.** `str_builder` is the core
string-building primitive, so *every* concurrent path that builds a string
corrupts — HTTP response framing (`sandhi_server_send_response_c`), JSON
(`json_v_build`), logging, formatting. It makes any cyrius multi-threaded server
(sandhi, this probe) silently return corrupt bytes under load. This sits
**upstream of** the sigil/patra/sandhi concurrency findings — it's a foundational
core-stdlib blocker.
**Component:** `lib/str.cyr` — `str_builder_new_a` / `str_builder_add_cstr_a` /
`str_builder_build_a` (and whatever they transitively miscompile to). NOT the
allocator, NOT memcpy, NOT general codegen (all ruled out below).

## Symptom (real workload)

A 4-worker sandhi HTTP server (`sandhi_server_run_pooled`) hit with ~300
concurrent `curl`s to a **static** `/api/health` handler (no DB, no route params,
no app lock — just `json_v` + `resp_json` → `str_builder` → send) returns **~3%
corrupt responses** with cross-field byte interleaving:

```
{"status":"ok","service":"yeo-cy-test","version":"0.1.0"}      ← expected
{"ctatye":"-t","servire":"yeo.c1.0est","version":"0.1.0"}      ← got (~3%)
{"status":"ok","servict":"seo-coktest","vireion":"-c1.0"}      ← got
```

("yeo.c1.0est" = "yeo-cy-test" spliced with "0.1.0" — two field buffers sharing
overlapping memory.)

## Bisection (the decisive evidence)

A minimal N-thread test (below), 8 threads × 40 000 iterations each, every worker
writing **thread-unique** bytes and re-verifying:

| Operation under test | corrupt count |
|---|---|
| bare `alloc()` (write id, re-read) | **0** |
| `alloc_via(default_alloc(), …)` | **0** |
| `memcpy` (per-thread buffers) | **0** |
| **hand-rolled str_builder replica** — same struct layout, same `alloc_via(default_alloc())` seam, manual append/build | **0** |
| **`str_builder_new_a` + `add_cstr_a` + `build_a` (inline, ≤64B, no grow)** | **~280 000 (~87%)** |
| **`str_builder_*` (grows inline→heap, ≥100B)** | **~280 000 (~87%)** |
| `str_builder_*` single-threaded (N=1) | **0** |
| `str_builder_*` at N=2 | **~50%** |

**The smoking gun:** a **byte-identical hand-rolled replica** — same 88-byte
struct (`alloc_via(default_alloc(),88)`, `data=hb+24`, `len`, `cap`), same append
(`load64`/`store8`/`store64`), same build (`alloc_via`+`memcpy`) — is **100%
clean across millions of ops**, while the `str_builder` *library functions* with
the same logic corrupt ~87%. So it is **not** the allocator (proven clean both
bare and via `default_alloc`), **not** memcpy, **not** general codegen (the
equivalent inline code is clean) — it is specific to the `str_builder` library
functions. Growth is not required (the inline ≤64-byte path corrupts identically),
and it is 0% single-threaded.

Because the source of those functions reads as correct/per-call (each builder is
an independent allocation; no module-global state is visible), the byte-identical-
replica-is-clean result points at a **compiler miscompilation of these specific
functions under the concurrent call pattern** (e.g. a caller-saved-register or
stack-frame bug across the nested `str_builder_*`→`strlen`/`_sb_grow_a`/`memcpy`/
`str_new_a` call chain), or a hidden shared state the source doesn't surface.

## Minimal reproduction

```
# str_builder corrupts under concurrency; a hand-rolled equivalent does not.
var N = 8;  var ITERS = 40000;
var g_sb = 0;  var g_manual = 0;  var g_done = 0;

fn check(p, sz, b): i64 { var j=0; while (j<sz) { if (load8(p+j)!=b) {return 1;} j=j+1; } return 0; }

fn worker(arg): i64 {
    var id = load64(arg);
    var ch[2]; store8(&ch, 65 + id); store8(&ch + 1, 0);   # per-thread 1-char cstr
    var i = 0;
    while (i < ITERS) {
        var a = default_alloc();
        # --- str_builder library path ---
        var sb = str_builder_new_a(a);
        var m = 0; while (m < 40) { str_builder_add_cstr_a(a, sb, &ch); m = m + 1; }
        if (check(str_data(str_builder_build_a(a, sb)), 40, 65 + id) != 0) { atomic_fetch_add(&g_sb, 1); }
        # --- hand-rolled equivalent (same logic, same alloc_via seam) ---
        var hb = alloc_via(a, 88); store64(hb, hb + 24); store64(hb + 8, 0); store64(hb + 16, 64);
        var dm = 0;
        while (dm < 40) { var dl = load64(hb + 8); store8(load64(hb) + dl, 65 + id); store64(hb + 8, dl + 1); dm = dm + 1; }
        var dt = load64(hb + 8); var dout = alloc_via(a, dt + 1);
        var k = 0; while (k < dt) { store8(dout + k, load8(load64(hb) + k)); k = k + 1; }
        if (check(dout, 40, 65 + id) != 0) { atomic_fetch_add(&g_manual, 1); }
        i = i + 1;
    }
    atomic_fetch_add(&g_done, 1);
    return 0;
}
fn main() {
    alloc_init();
    var args = alloc(N * 8); var k = 0;
    while (k < N) { store64(args + k*8, k + 1); thread_create(&worker, args + k*8); k = k + 1; }
    while (load64(&g_done) < N) { syscall(24, 0, 0, 0, 0); }
    print("sb_fail     = ", 14); fmt_int(g_sb); println("");
    print("manual_fail = ", 14); fmt_int(g_manual); println("");
    return 0;
}
var rc = main(); syscall(SYS_EXIT, rc);
```

Observed (cyrius 6.3.1, Linux x86_64): `sb_fail ≈ 280000`, `manual_fail = 0`.
(Deps: stdlib `alloc`,`str`,`thread`,`atomic`,`fmt`,`io`,`syscalls`.)

## Blast radius

Any concurrent `str_builder` use corrupts. Confirmed via sandhi's HTTP server
(every `sandhi_server_send_response_c` frames through `str_builder`) and the
probe's `json_v_build`. Fixing this is the precondition for a correct cyrius
concurrent server.

## Second manifestation — this gate also unblocks multi-worker server TLS (2026-06-30)

Tracking note so the v6.3.13 fixer verifies both paths. With **sigil 3.9.7**
(concurrent-TLS crypto crash fixed — auto-banking; folded in 6.3.12), a
multi-worker HTTPS server (`sandhi_server_run_pooled_tls`, `max_conns ≥ 2`) no
longer crashes but **every concurrent request fails with `SSL: BAD_SIGNATURE`**.
Cause is this same str_builder bug, surfacing differently over TLS: two workers'
`str_builder`-built response buffers **overlap** (the race), so one worker mutates
its buffer *while* `tls_native_write` is encrypting + MAC-ing it → the record MAC
no longer matches the transmitted ciphertext → the client rejects it as
`BAD_SIGNATURE`. Ruled out as a TLS bug: `tls_native_hs13` has **zero**
module-global scratch (per-ctx), and sigil's own `concurrent_tls_handshake` /
`banking_concurrent` / `ecdsa_concurrent` tests pass 18/18.

- **Reproduction:** `yeo-cy-test` (consistent 6.3.12 via `cyrius lib sync --full`),
  TLS pool `max_conns=4`: concurrency 1 → ok; ≥2 → `SSL: BAD_SIGNATURE`, server
  stays alive. At `max_conns=1` (serialized response building) HTTPS is clean.
- **When fixing this gate, add a multi-worker-TLS regression test** (concurrent
  HTTPS over `run_pooled_tls`, `max_conns>1`, asserting clean handshakes + bodies),
  not just the HTTP/`str_builder` repro above — they fail differently
  (HTTP: garbled-but-decryptable JSON; HTTPS: `BAD_SIGNATURE`).
- **Consumer status:** `yeo-cy-test` keeps its TLS pool at `max_conns=1` until this
  lands; the plan is to bump it to 4 the moment v6.3.13 ships. Tracked probe-side in
  `yeo-cy-test/FINDINGS.md` + the `src/main.cyr` serve-loop comment.
