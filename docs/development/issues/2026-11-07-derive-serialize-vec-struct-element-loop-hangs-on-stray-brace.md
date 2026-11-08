# `#derive(Serialize)`'s `<Name>_from_json_str` loops forever on a `Vec<struct>` array holding a stray `}` — OPEN

**Status:** 🔴 **OPEN**: reported by svara, whose 3.6.3 fuzz target found it.
**Placement:** unpinned — 6.x-line backlog.
**Where the fix lives:** the `Vec<struct>` arm of the `_from_json_str` emitter, `src/frontend/lex/pp/serialize.cyr:514`
at 6.7.18.
**Discovered:** 2026-11-07, during svara 3.6.3's P(-1) sweep (fuzz case 82, a mutated `SvProsodyContour` document).
**Reporter:** svara 3.6.3
**Cyrius version at time of report:** 6.7.18
**Severity:** High. Hostile input puts the decoder in an endless loop. It does not fault, and it does not abort,
because nothing is allocated per turn. It is the same class of defect as
[`2026-11-07-derive-serialize-key-scan-reads-past-nul.md`](2026-11-07-derive-serialize-key-scan-reads-past-nul.md), in
the `Vec<struct>` scans that issue left unaudited.
**Affects:** cycc 6.6.0 through 6.7.18. The repro gives the same 3 wrong rows on 6.6.0, 6.6.20, 6.7.9 and 6.7.18, each
built with that version's own `lib/`. 6.6.0 is the oldest toolchain installed here. The arm dates from 6.4.13 (R3).

## Summary

For a `Vec<struct>` field, the emitted element loop is:

```
while (1 == 1) {
    skip ' ', '\n', '\r', '\t', ','
    var _ec = load8(json + _p);
    if (_ec == 93 || _ec == 0) { break; }               # ']' or NUL
    if (_ec == 123) { decode one element, walk to its '}' }
    else { _p = _cy_json_skipval(json, _p); }
}
```

`_cy_json_skipval` stops without consuming anything at a depth-0 `,`, `}` or `]` (its own comment says so, `:88`).
So when the byte at element position is `}`, it returns `_p` unchanged, and the loop meets the same `}` again
forever. The guard is missing in only this case: a `,` is skipped by the loop, and `]` breaks out of it.

Three documents reach it:

- `[}]`: the `}` is at element position from the start.
- `[1}]`: `skipval` walks `1`, then stops at the `}`.
- `["time":0.0,"value":0.85}, ...]`: an element that has lost its `{`. `skipval` walks to the first `,`, the loop
  skips that, then `skipval` walks `"value":0.85` and stops at the `}`.

The fuzzer found the third shape: one byte of a valid contour changed, `{` to `\x1a`.

## Reproduction

[`repros/2026-11-07-derive-serialize-vec-struct-element-loop-hangs-on-stray-brace.cyr`](repros/2026-11-07-derive-serialize-vec-struct-element-loop-hangs-on-stray-brace.cyr)
derives `Serialize` on `Curve { points: Vec<Pt>; scale: f64; }`. Each row decodes in a forked child under
`alarm(2)`, so a hang becomes a wrong row and the repro still finishes. The exit code is the number of wrong rows.

```
cyrius build docs/development/issues/repros/2026-11-07-derive-serialize-vec-struct-element-loop-hangs-on-stray-brace.cyr /tmp/derive-vec-hang
/tmp/derive-vec-hang; echo "exit=$?"
```

Actual, on 6.7.18, built from a scratch directory holding 6.7.18's `lib/` snapshot:

```
  ok    valid, 2 points              returned
  ok    valid, empty list            returned
  WRONG [}]                          still running after 2 s (killed by SIGALRM)
  WRONG [1}]  (a scalar, then '}')   still running after 2 s (killed by SIGALRM)
  WRONG ["time":0.0,"value":0.85}]  still running after 2 s (killed by SIGALRM)
wrong rows: 3
exit=3
```

Expected: every row returns, with a struct or with 0, and the repro exits 0. The two control rows pass either way.

## Root cause

`serialize.cyr:514` emits `} else { _p = _cy_json_skipval(json, _p); }` as the element loop's fallback, with no
check that it moved `_p`. The `Vec<int>` and `Vec<f64>` helpers have that check. At `:63–67` the emitter says why:
a byte the loop cannot consume "would otherwise leave p unmoved and spin the outer loop forever", so the helper
skips the byte when nothing was consumed. The `Vec<struct>` arm did not get the same guard.

The non-array fallback at the end of `:514`, and the skips at `:574`, `:578` and `:612`, return to the key loop,
which handles a `}` itself. The repro does not exercise them. Nested-struct values (`:598`) were not audited.

## Proposed fix (not tested)

Give the fallback the forward-progress guard that the `Vec<int>` helper already has:

```
} else { var _sp<fi> = _p; _p = _cy_json_skipval(json, _p); if (_p == _sp<fi>) { _p = _p + 1; } }
```

A stray byte is then skipped, as it is in `Vec<int>`. Breaking out of the loop on `_ec == 125` would also end the
hang, but it would close the array early. Neither change was built into a compiler here. The repro's rows are
the regression check.

## Who is exposed

Two repos derive `Serialize` on a struct with a `Vec<struct>` field: svara (7 types: `SvProsodyContour`,
`SvPhonemeSequence`, `SvVocalTractState`, `SvTrajectoryState`, `SvBatchRendererState`, and the pool and synth-context
states) and garjan (1 file). In svara the hang comes before validation: `svara_tract_restore` validates the state
that `SvVocalTractState_from_json_str` returns. `{"formants":[}],"sample_rate":44100.0}` never returns from the
decoder, so the restore entry svara documents for untrusted JSON never runs.

## Consumer-side workaround

None shipped. A caller decoding JSON it did not write can bound the decode with a timeout, or check the document
itself before decoding.
