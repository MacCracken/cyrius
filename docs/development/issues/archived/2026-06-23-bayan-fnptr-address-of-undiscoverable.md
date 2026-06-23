> **RESOLVED v6.2.38** — "Obtaining a function pointer" note (`var fp = &fn_name;`
> + `fncallN`/`callptr`) added to the `lib/fnptr.cyr` header (travels with the pin).
> See CHANGELOG [6.2.38].

# bayan: how to obtain a function pointer (`&fn`) is undiscoverable from consumer-facing materials — Filed

**Discovered:** 2026-06-23 during bayan 1.0.3 (making the JSON value + streaming
parsers reentrant; writing a regression test for the streaming-parser callbacks).
**Severity:** Low — doc-locality / ergonomic papercut. The wrong guess produces a
misleading `undefined variable` error, and a consumer shipped a weaker test as a
stopgap. No miscompilation; `&fn` itself works correctly.
**Affects:** cycc 6.2.37 (consumer's pin) and every prior version that ships
`lib/fnptr.cyr`. The gap is in what travels with a pinned toolchain snapshot, not
in the compiler.

## Summary

Wiring up the JSON streaming parser's event callbacks requires passing a
**function pointer** to `bayan_json_stream_on(handler, event_id, fp)`, later
dispatched via `fncallN(fp, ...)`. The correct idiom is the address-of operator,
`&function_name`. That idiom appears **nowhere** in the materials a downstream
repo actually has at its toolchain pin:

- **`lib/fnptr.cyr`** — vendored into every consumer via `[deps] stdlib` — documents
  the *calling* side exhaustively (`fncall0..8`, full per-target ABI register
  layout) but never states how to *obtain* an `fp`. Its header says only "Call a
  function through a pointer stored in a variable"; there is no `var fp = &fn;`
  anywhere in the file. `grep -niE '&fn|address|obtain' lib/fnptr.cyr` → 0 hits.
- The **streaming-handler doc block** (now in bayan's `src/json.cyr`, carved from
  cyrius `lib/json.cyr`) lists 11 slots as `fnptr or 0` with their `fncallN(...)`
  shapes, but shows no example of producing one.

The `&fn` idiom *is* documented in `docs/guides/cyrius-guide.md` (§Function
Pointers) and exercised in `tests/tcyr/json_stream.tcyr`
(`bayan_json_stream_on(h, JS_EV_INT, &cb_int)` — all 11 callbacks registered with
`&cb_*`). But a consumer that pins a **toolchain snapshot** receives `lib/` only —
`~/.cyrius/versions/<X>/` ships `bin/ lib/ programs/ VERSION`, no `tests/`, no
`docs/`. So the one fact the caller needs is exactly the one not in reach.

Net effect: I could not discover `&fn` from the consumer side and shipped a weaker
stopgap test (see workaround), leaving bayan's streaming **callback-dispatch** path
(`fncallN(fp, ...)` per event) untested in bayan's own suite.

## Reproduction

A caller wants an `on_int` accumulator callback:

```cyrius
fn on_int(ctx, n) { store64(ctx, load64(ctx) + n); return 0; }
# ...
var h = bayan_json_stream_handler_new(&acc);
bayan_json_stream_on(h, JS_EV_INT, on_int);    # intuitive — and WRONG
```

Actual:

```
error: undefined variable 'on_int' (missing include or enum?)
```

A misleading message — the function plainly exists. Nothing in the vendored
`lib/fnptr.cyr` header or the streaming-handler doc hints that the fix is a single
`&`:

```cyrius
bayan_json_stream_on(h, JS_EV_INT, &on_int);   # correct
```

A first-time consumer (building against a pin, no repo checkout) has no in-reach
pointer to that `&`.

## Root cause (if known)

Not a language/compiler defect — `&fn_name` works correctly (lexer ampersand
token; `src/frontend/parse_expr.cyr` `&var`/`&fn` handling with the
local → global → function resolution order; backend "function address" fixup).
It is a **documentation-locality gap**: the obtain-a-function-pointer idiom is
documented only in artifacts (`docs/guides/`, `tests/tcyr/`) that do **not** ship
with a pinned toolchain snapshot, while the file that *does* ship with every
consumer (`lib/fnptr.cyr`) omits it.

## Proposed fix

Cheapest durable fix that helps every consumer: add a short "Obtaining a function
pointer" note to the **`lib/fnptr.cyr` header** (it travels with the pin), e.g.:

```cyrius
# Obtaining a function pointer — use the address-of operator on the name:
#     fn add(a, b) { return a + b; }
#     var fp = &add;             # &fn_name  (a BARE `add` is "undefined variable")
#     fncall2(fp, 10, 20);       # or callptr(fp, 10, 20)  (v6.0.70+)
# See docs/guides/cyrius-guide.md#function-pointers.
```

This converts the misleading `undefined variable` dead-end into a one-line answer
at the exact place a consumer is already looking when they reach for `fncallN`.
(The streaming-handler doc block could mirror a "register with `&fn_name`" line,
but that block now lives in bayan — bayan will carry that half.)

## Consumer-side workaround (if any)

bayan 1.0.3 first shipped a **no-callback streaming driver test** (register zero
callbacks, assert only the `0` / `-1` return) because `&fn` wasn't discoverable
from the consumer side. Once the idiom was confirmed (`docs/guides/cyrius-guide.md`
§Function Pointers; `tests/tcyr/json_stream.tcyr` registers all 11 callbacks with
`&cb_*`), bayan **replaced** it with a real-callback test that registers handlers
via `&_strm_cb_*` and asserts per-event dispatch — so this is no longer blocking
bayan. It is filed because the **discoverability gap is still live for the next
consumer**: nothing in the materials that travel with a pinned snapshot
(`lib/fnptr.cyr` + the streaming-handler doc) points to `&fn`. The durable fix is
the `fnptr.cyr` header note above; until it lands, a consumer's only path to the
idiom is a full cyrius repo checkout (guide + `tests/tcyr/`), which a pin doesn't
provide.
