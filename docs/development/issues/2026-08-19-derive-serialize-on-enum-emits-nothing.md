# `#derive(Serialize)` on an enum compiles clean and emits no codec at all

**Status:** 🟡 **OPEN** — found re-verifying a stale note during ranga's M7 parity audit.
**Placement:** unpinned — 6.5.x backlog. Derive expansion, not stdlib.
**Discovered:** 2026-08-19, ranga M7 (the port hand-writes four enum codecs because of this)
**Severity:** **Medium** — silent. rc=0, no diagnostic, and the absence only surfaces at link time.
**Affects:** cycc 6.5.27

## Summary

`#derive(Serialize)` above a **struct** works: the codec is generated and callable.
Above an **enum** it compiles with rc=0 and no diagnostic, and generates **nothing** — the
`<name>_to_json` the caller expects is undefined at link time.

```
#derive(Serialize)
struct probe_s { a; b; }

#derive(Serialize)
enum probe_e { PE_ONE = 0; PE_TWO = 1; }
```

`cyrius test` on that alone: **exit 0**, no warning about the enum.

Add a call and the difference appears:

```
var js = probe_s_to_json(p);        # fine
var je = probe_e_to_json(PE_TWO);   # warning: undefined function 'probe_e_to_json'
                                    # error: refusing to emit binary with 1 reachable undefined function(s)
```

So the derive is accepted, silently does nothing, and the consumer discovers it only when
something actually calls the codec — potentially long after the derive was written.

## Why this is worth a diagnostic rather than documentation

The derive is *accepted*. A reader has every reason to believe it worked: it is spelled
the same as the struct form that does work, in the same file, and the build is green.
Nothing distinguishes "derive applied" from "derive ignored" until link time, and if the
codec is only called on a cold path, not even then.

Rejecting it — `error: #derive(Serialize) is not supported on enum 'probe_e'` — would be
strictly better than the current silence, even if enum support never lands.

## History — the symptom has changed, so a stale note misled us

ranga's port plan (`docs/development/cyrius-port-plan.md` §3 item 6) has recorded since the
port began that this "compiles rc=0 with no diagnostic and produces a **misnamed, crashing
codec**". On 6.5.27 that is no longer what happens: there is no codec to be misnamed, and
nothing to crash. The conclusion for consumers is unchanged — hand-write enum codecs — but
the recorded symptom was wrong, and it was only caught because the M7 audit re-tested the
claim instead of quoting it. Filing partly so the current behaviour is written down
somewhere authoritative.

## Proposed fix

In priority order:

1. **Support it.** A C-like enum is an integer with names; `to_json`/`from_json` over it is
   the name↔value table the compiler already has.
2. **Failing that, reject it loudly** at the derive site, naming the enum and the
   unsupported derive.
3. At minimum, **warn**.

What should not happen is silent acceptance of a derive that does nothing.

## Consumer-side workaround

Hand-write the codec, following the `device_class_to_str` pattern in `lib/yukti.cyr:640`.
ranga does this for four enums (`PixelFormat`, `BlendMode`, `ColorSpace`, and one payload
enum); the Display side is `pixel_format_name` / `blend_mode_name` and the parse side is
simply absent, which the parity audit records as a real gap against the Rust line — Rust's
`FromStr` lets a consumer turn `"Multiply"` back into a `BlendMode`, and the port cannot.
