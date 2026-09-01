# Vendored `lib/sandhi.cyr` silently drops whole SSE events at read boundaries — re-vendor from sandhi 1.9.15

**Status:** 🟠 **OPEN** — fixed upstream in **sandhi 1.9.15** (2026-08-27); reaches consumers only when a
cyrius release re-vendors `lib/sandhi.cyr` from `dist/sandhi.cyr`. No compiler work requested.
**Placement:** next 6.5.x patch — this is a re-vendor, not a language or codegen change.
**Discovered:** 2026-08-27 while chasing a thoth 0.44.2 bug report ("asking the model to review a project
gets stuck").
**Severity:** **High for SSE consumers** — silent data loss: no error, no short read, nothing the caller
can detect. No impact on anyone not reading Server-Sent Events.
**Affects:** cycc 6.5.35 and every earlier release whose vendored `lib/sandhi.cyr` is ≤ sandhi 1.9.14
(the copies in thoth's and hoosh's trees both read `SANDHI_VERSION = "1.9.10"`).

## Summary

`sandhi_sse_parse_a` reports, via `remaining_out`, how many bytes a streaming caller may drop from its
buffer. It advances that offset past **every complete line** — including lines belonging to an event it
has not dispatched. But the field context accumulating those lines is created **per call** and discarded
on return, so a caller that trusts `remaining_out` throws away the only copy of a half-built event. The
next call starts after those bytes with an empty context, reaches the event's blank line, finds no
fields, and dispatches nothing.

The symptom is that **an entire SSE event vanishes** from a stream that is otherwise complete and
well-formed. It is intermittent, because it happens only when a TCP read boundary lands after a field
line and before the blank line ending that event — which on a busy stream is several times a minute.

## Reproduction

Against the vendored `lib/sandhi.cyr` (any snapshot ≤ 1.9.14):

```cyrius
# repro.cyr — expected: 1 event, remaining = 13.  actual: 1 event, remaining = 49.
fn main() {
    var raw = "data: first\n\nevent: block_start\ndata: {\"id\":\"x\"}\n";
    var rem = alloc(8);
    var events = sandhi_sse_parse(raw, strlen(raw), rem);
    print_int(vec_len(events));   # 1  — correct, the second event is not complete yet
    print_int(load64(rem));       # 49 — WRONG: 13 expected (past "data: first\n\n" only)
    return 0;
}
```

`49` tells the caller to drop the `event:`/`data:` lines of the open event. Feed the remainder plus the
blank line back in, as `_sandhi_stream_feed_sse_a` does, and the second event never appears.

End-to-end, driving the parser exactly the way the streaming loop drives it (append chunk → parse → drop
`remaining_out` → repeat) over a stream split at the boundary:

```
chunk 1: "event: message_start\ndata: {…}\n\nevent: content_block_start\ndata: {…}\n"
chunk 2: "\nevent: content_block_delta\ndata: {…}\n\n"

expected: 3 events   actual: 2 events — content_block_start is gone
```

This is `test_sse_stream_loop_no_event_lost` in sandhi 1.9.15's suite; it fails on 1.9.14.

The pre-existing `test_sse_partial_trailing_event` does **not** catch this: its partial event
(`"data: partial"`) has no terminator, so it takes the `line_end < 0` path and correctly consumes
nothing. The failing case needs a partial event whose lines *are* terminated.

## Root cause

`sandhi_sse_parse_a`, in the non-empty-line branch of the line loop (upstream
`src/http/sse.cyr` ~line 332; in the vendored bundle, the same function inside `lib/sandhi.cyr`):

```cyrius
} else {
    _sandhi_sse_apply_line_a(a, ctx, buf, pos, line_end);
    consumed = line_end;          # ← unconditional: consumes lines of an UNDISPATCHED event
}
```

`ctx` is allocated at the top of the same function and never returned, so everything
`_sandhi_sse_apply_line_a` folded into it is lost when the call returns — while `consumed` has already
told the caller those bytes are dealt with. Not speculation: verified by the failing assertions above.

## Proposed fix

Already implemented upstream in sandhi 1.9.15 — consume a line only when it left **no pending event
state**:

```cyrius
} else {
    _sandhi_sse_apply_line_a(a, ctx, buf, pos, line_end);
    if (load64(ctx + _SANDHI_SSE_CTX_OFF_HAS_FIELDS) == 0) { consumed = line_end; }
}
```

Comment-only keep-alive traffic still drains (a comment sets no fields, so it is consumed on sight and a
caller's buffer cannot grow without bound); a line belonging to an open event stays put until that event
is dispatched.

**The ask on cyrius is only to re-vendor** `lib/sandhi.cyr` from sandhi 1.9.15's `dist/sandhi.cyr`.
sandhi 1.9.15: **2,866 assertions** (was 2,851), 8/8 fuzz, five dist bundles regenerated idempotently,
`cyrius lint` clean, smoke + `CYRIUS_DCE=1` builds green. No API or signature change.

Verify after the re-vendor:

```sh
grep -c 'HAS_FIELDS) == 0) { consumed' lib/sandhi.cyr   # 1
grep    'var SANDHI_VERSION' lib/sandhi.cyr             # "1.9.15"
```

## Consumer-side workaround (if any)

**None that closes it.** A consumer cannot fix the parser without editing vendored `lib/`, which
first-party projects are forbidden to do. What consumers *can* do — and what thoth 0.44.2 shipped — is
refuse to propagate the damage:

- Never emit a tool call whose name never arrived; drop it, and say so.
- Treat an empty-string tool name as no name.
- Report an HTTP 200 stream that carried no usable frames as a **gateway** fault rather than a model
  answer.

That converts a bricked session into one lost round, which is the difference between "the agent is
broken" and "one call was dropped, it will retry" — but the frames are still lost until the re-vendor.

## How it surfaced

Two first-party consumers, neither able to see the cause from where it sat:

1. **hoosh** proxies Anthropic's streaming API. It lost the `content_block_start` frame carrying a tool
   call's `id` and `name` while that call's `input_json_delta` fragments survived, and forwarded
   **arguments belonging to a call with no name**.
2. **thoth** echoed that call into its conversation, where the provider rejects a `tool_use` block with an
   empty `id` and `name`. Every later request in that conversation then returned an empty completion —
   so one dropped frame bricked an entire agent session, with the symptom appearing many rounds after the
   cause. It looked like a model failure, then like a hoosh failure, before the wire capture showed the
   frame had never been delivered.
