# Cyrius: parser intermittently emits `expected ')', got string` on `assert(streq(call(args, n), "lit") == 1, "msg")` shape

**Filed:** 2026-05-10
**Reporter:** bote (MCP core service, v2.7.1)
**Cyrius version at time of report:** 5.10.34 (release tarball + source archive)
**Affected stage:** parser, `cc5`
**Severity:** **Low** — has a one-line workaround (stage the inner call
into a `var`). The annoying part is the misleading error message
(`expected ')', got string`) points the consumer at the wrong fix
(rebalance quotes, escape backslashes, etc.) and a fair amount of
bisect time evaporates before the var-stage rescue becomes obvious.
The error position also drifts when surrounding lines change, which
suggests the parser's position-tracking is racing somewhere.
**Status:** open. **Expected target:** **5.11.x arc**.

## Summary

While porting `tests/bote_host.tcyr` to add HostRegistry hot-reload
coverage (bote 2.7.1), the parser failed on a construct that shows
up everywhere else in the bote test suite and compiles fine in
isolation:

```cyrius
# Fails inconsistently with "expected ')', got string"
assert(streq(vec_get(caps_v, 0), "fetch") == 1, "cap idx 0 is fetch");
```

The construct is `assert( fn( fn_with_2args(a, b) , LITERAL) == 1, LITERAL )`.
The outer `assert` is `lib/assert.cyr::assert(cond, name)` — 2 args.
The inner `streq` is 2 args. The doubly-inner `vec_get` is 2 args.

The same shape with a 1-arg inner call parses fine and is used
throughout bote's test suite:

```cyrius
# Parses fine
assert(streq(host_entry_name(e), "github") == 1, "entry name");
```

The shape with the inner 2-arg call **also parses fine in many test
files**:

```cyrius
# Parses fine in src/host.cyr internal use
if (streq(vec_get(caps, i), cap) == 1) { return 1; }
```

So it isn't every occurrence — only some, depending on what comes
*before* in the compile unit. bote's bisect (chunk-by-chunk re-add
of the new tests) showed the error position drifting from line 187
to 184 to 178 to 173 as preceding lines were added/removed, but the
error message and "got string" symptom stayed identical.

## Reproduction

Bote's bisect didn't isolate a minimal repro before the var-stage
workaround unblocked the patch. The reproducible signal during the
bisect was: "add the test block at the end of a `.tcyr` file with
many earlier asserts, error appears; refactor the inner call to a
`var` two lines above, error disappears". After full chunk-by-chunk
re-add, the error stopped reproducing — suggesting the parser hits
this state path-dependently (some specific tokenizer state during a
preceding line carries forward and only the `assert(streq(call(args,
n), "lit") == 1, ...)` shape exposes it).

The hand-narrowed test file at the moment of the bisect (before
the workaround):

- `tests/bote_host.tcyr` at ~180 lines of assertions including
  long SSRF URL string literals (`"http://[64:ff9b::1.2.3.4]/"`,
  `"http://2130706433/"`, etc.) preceding the new block.
- The new block at the end added a 2-arg-inner-call shape against
  `vec_get`.
- Removing all the new block restored parse; var-staging the inner
  call restored parse without removing the assertions.

bote-side workaround that ships in 2.7.1:

```cyrius
# Note: parser quirk in cyrius 5.10.x — nesting a 2-arg call inside
# another call inside `assert` ("expected ')', got string" at the
# outer fn boundary). Stage into a var first; same behaviour, parses.
var cap0 = vec_get(caps_v, 0);
var cap1 = vec_get(caps_v, 1);
assert(streq(cap0, "fetch") == 1, "cap idx 0 is fetch");
assert(streq(cap1, "tools_call") == 1, "cap idx 1 is tools_call");
```

Documented in bote's `CONTRIBUTING.md` (2.7.1 cleanup) under
**Code Style**:

> No nested 2-arg call inside `assert(...)` inside `streq(...)`
> with certain JSON literal contexts — the 5.10.x parser
> occasionally chokes (`expected ')', got string`). Stage the inner
> call into a `var` first; same behaviour, parses.

## Root cause (speculation — flag for verification)

Two hypotheses, both speculation; the cyrius agent has the parser
internals:

1. **String literal tokenizer is bleeding state across recursive
   call descent.** When the parser is mid-way through resolving the
   `streq(...)` argument list and encounters the string literal
   `"fetch"`, something about the surrounding `vec_get(caps_v, 0)`
   pre-context confuses the position counter on the *next* token.
   The "got string" symptom is the next token (`"cap idx 0..."`)
   being tokenized as a string at the wrong call-stack position.
2. **Fixup-table interaction with a specific identifier count.**
   The error position drifts when preceding lines change, suggesting
   a position-tracking dependency on cumulative ident-table or
   fixup-table state. fn_table at the error site was 339-342 (very
   small — the parser hadn't done much yet), but identifiers were
   at ~8700, which is enough for a hash collision or scan-window
   boundary to bite.

Either way, the **misleading error message** (`expected ')', got
string`) is itself the bug the consumer cares about — the underlying
parser issue might be benign-modulo-position-tracking, but the
diagnostic sends consumers down the wrong rabbit hole.

## Proposed fix

Two layers, either or both:

1. **Fix the underlying tokenizer/position-tracking state leak.**
   If the cyrius agent can identify the path-dependent trigger,
   ideal outcome.
2. **Improve the diagnostic** when the parser hits "expected `)`
   got string in fn-arg list". A message like:
   > `expected ')' before string literal "cap idx 0 is fetch" — possible nested-call disambiguation issue; stage the inner expression into a `var` and retry`
   would have saved bote ~45 minutes of bisect. The diagnostic
   doesn't have to identify the *correct* fix; just gesturing at
   "this is the var-stage workaround zone" is enough.

## Consumer-side workaround

**Shipped, documented.** The var-stage workaround is a 2-line
diff per affected assertion. bote 2.7.1 uses it in
`tests/bote_host.tcyr` lines 175-183 (the new HostRegistry
hot-reload coverage) and documents the pattern in
`CONTRIBUTING.md` under Code Style.

No correctness or performance impact — the `var` lifetime is
identical to the inlined expression's lifetime, and cyrius's DCE
should optimize away the named binding if it ever matters.

## Severity rationale

**Low** because:

- **Has a working stopgap** (`var`-stage). bote shipped 2.7.1 on it.
- **No correctness risk** — the parser fails closed (compile error),
  never accepts the malformed parse silently.
- **Low frequency** — bote only hit this once in the entire 2.x
  porting cycle. Most consumers won't trip it.

Bumps to **Medium** if:

- A second consumer reports the same diagnostic with a different
  trigger shape (suggesting the path-dependence is more general).
- The misleading-diagnostic burden compounds — e.g. if it starts
  showing up in `cyrius lint` / `cyrius fmt` output too.

## Pointers

- bote `tests/bote_host.tcyr` lines 175-183 — the var-stage workaround
  in production.
- bote `CONTRIBUTING.md` — the documented warning under Code Style.
- bote 2.7.1 CHANGELOG — "Notable parser detour" section.
