# cc5 PP_IFDEF_PASS 2MB Expanded-Source Cap Blocks Sit on Sandhi-Folded Stdlib

**Discovered:** 2026-05-12 during sit v0.7.6 → v0.8.x preparation (cyrius pin 5.9.37 → 5.11.31)
**Severity:** Medium — sit cannot build against any 5.10.x+ toolchain on a stock `[deps].stdlib` that lists `sandhi`. Consumer workaround forces source-level surgery (drop sandhi, hand-roll the HTTP/1.0 server).
**Affects:** cc5 ≥ 5.7.0 (the sandhi-fold) through 5.11.32. Latency of impact grew silently as sandhi accreted TLS 1.3 0-RTT (v1.3.2), session-cache cred-strip (v1.3.3), and annotation pass (v1.3.4) — the consumer's expanded source crossed the 2 MB cap somewhere in this window without a flagged release.

## Summary

`cc5` raises `error: expanded source exceeds 2MB (NNNN bytes) in PP_IFDEF_PASS iter=0` when the preprocessor's concatenated expansion of `[deps].stdlib` + `[deps.X]` crates + project `src/*.cyr` crosses 2,097,152 bytes. Sit's expansion under cyrius 5.11.31 with the documented stdlib list (`sandhi` + transitives `tls` / `ws` / `http` / `json`) measures **2,099,593 bytes — 2,441 over the cap.** No project-side source changes; pure stdlib growth.

## Reproduction

```sh
cd /home/macro/Repos/sit
git checkout 875d1fa  # post-v0.7.6 HEAD as of filing
# edit cyrius.cyml: cyrius = "5.11.31"
rm -rf lib && cyrius update      # populates from ~/.cyrius/versions/5.11.32/lib (5.11.31 not installed locally; same outcome)
cyrius build src/main.cyr build/sit
```

Expected: clean build (sit v0.7.6 source unchanged from its passing state on cyrius 5.9.37).

Actual:

```
compile src/main.cyr -> build/sit [x86_64] note: cwd ./lib/ shadows version-pinned /home/macro/.cyrius/versions/5.11.31/lib/ — delete ./lib/ to use the version-matched snapshot, or set CYRIUS_NO_WARN_SHADOW_LIB=1 to silence this note
error: expanded source exceeds 2MB (2099593 bytes) in PP_IFDEF_PASS iter=0
FAIL
```

`lib/sandhi.cyr` measures 11,729 lines under both 5.11.25 and 5.11.32. Sit's `src/serve.cyr` calls 6 sandhi primitives: `sandhi_server_run`, `sandhi_server_get_method`, `sandhi_server_get_path`, `sandhi_server_path_only`, `sandhi_server_send_response`, `sandhi_server_send_status`. The remaining 11,500+ lines (TLS 1.3 0-RTT, HTTP/2, RPC dialects, retry, SSE, session-cache cred-strip) ride along through the preprocessor even after DCE strips them from the linker output.

## Root Cause

The 2 MB cap dates from the v4.8.4 retag (`readfile-512kb-cap.md`, archived) where `PP_IFDEF_PASS` gained a size guard to convert silent truncation into a clear error. At the time, `preprocess_out` was a 1 MB buffer and the cap was 1 MB; the doubling to 2 MB landed alongside the v5.7.0 sandhi fold (cap-buffer pair grew together).

What the cap *does* catch: malformed includes, runaway macro expansion, accidental directory recursion. What it now *also* catches: a stock-shape AGNOS consumer pulling stdlib that's grown past the cap on its own merits. The cap was sized for the pre-sandhi-fold stdlib; sandhi alone is now ~25% of the available budget.

## Recommendation

**Raise the cap to 4 MB (4,194,304 bytes).** Rationale:

- **Headroom for sandhi's TLS arc.** sandhi's first-party TLS (the "true cyrius TLS" replacement for the libssl shim) is in flight; once it lands the bundle grows again. 4 MB gives ~2× current sandhi-folded budget, enough to absorb the TLS rewrite + one more sandhi major.
- **Matches stdlib-math-recommendations precedent.** That issue raised a stdlib surface for a downstream that was re-rolling a tight 12-line loop in N consumers. The right answer was "the cap should accommodate the canonical shape," not "every consumer should work around it." Same shape here: the canonical shape is "list `sandhi` in `[deps].stdlib`"; the cap should accommodate it.
- **Per-include `READFILE` cap doubled from 512 KB → 1 MB in v4.8.4** for the same reason — buffer-and-cap pair growing with the canonical shape. The PP_IFDEF_PASS cap is the next link in that chain.

If 4 MB is too aggressive: **2.5 MB or 3 MB unblocks sit immediately** and defers the 4-MB conversation to when sandhi's TLS rewrite lands. The point is to unstick the canonical consumer shape, not to size-fit any specific consumer.

## Alternatives considered (sit side)

1. **Drop sandhi, hand-roll a ~500-line HTTP/1.0 server on `lib/net.cyr`** — fits the no-FFI thesis and matches the precedent sit already has on the client side (`wire_http.cyr` dodges stdlib `http_get`'s 64 KiB recv cap by building directly on `net`). Doable but defeats the point of sandhi being folded into stdlib for shared use.
2. **Sandhi modularize: `dist/sandhi-server.cyr` subset.** Plausible but moves the work into sandhi without addressing the root issue (the cap is the actual limiter; sandhi can only shrink so far before it's not server-shaped anymore).
3. **Reduce sit's `[deps].stdlib` to drop transitive entries** — cyrius v5.10.x SLOT 19 added transitive stdlib resolution, so in principle dropping `tls` / `ws` / `http` / `json` should work. In practice, dropping `tls` triggers `error: lib/sandhi.cyr:3629: undefined variable 'TLS_EARLY_DATA_ACCEPTED'` — transitive resolution doesn't follow enum / constant references through sandhi's TLS 1.3 0-RTT code path. (Separate filing-worthy item if SLOT 19's contract was meant to cover this.)

## Impact

- **sit v0.8.0** blocked. Sit is staying pinned at `cyrius = "5.11.31"` and accepting a red build until this resolves; the alternative is a v0.7.x-line drop-sandhi rewrite the consumer doesn't want to do for "fix the build" reasons.
- **Forward-compatibility for every AGNOS consumer that lists `sandhi`.** sandhi is canonical for service-boundary work across vidya / hoosh / ifran / daimon / mela / yantra / sit / ark per its own README. Every one of those will hit this cap with their own `src/*.cyr` budget added.
- **Filing tag in sit:** v0.8.x release notes will point at this issue; sit moves forward as soon as the cap raise ships in (per user) cyrius 5.11.33.
