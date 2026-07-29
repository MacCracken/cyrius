# `X(f(), …)` silently dispatches to `X_int` — a bare call result routes differently from a variable holding the same value

**Status:** 🟡 **OPEN** — verified against cyrius **6.4.86** on x86-64 Linux by A/B compiling
[`repros/2026-07-29-int-overload-call-result-misdispatch.cyr`](repros/2026-07-29-int-overload-call-result-misdispatch.cyr):
`take(make())` returns 2 where `var v = make(); take(v)` returns 1, with `take` and `take_int`
both defined. No warning at any verbosity; `cyrius lint` and `cyrius vet` are both silent.
**Placement:** unpinned — 6.x-line compiler backlog. The cheapest useful fix (a definition-site
warning) is independent of whether the dispatch rule itself changes.
**Discovered:** 2026-07-29 during the AgnosAI Rust→Cyrius port, milestone M4, while building
`src/tools_agnos.cyr`.
**Severity:** High — silently runs the wrong function body with no diagnostic. Not Critical only
because it requires the consumer to have defined an `X`/`X_int` pair, which is an opt-in naming
choice; see the honest scoping in **How wide is this really** below.
**Affects:** cyrius 6.4.86. Not bisected against earlier versions.

## Summary

A call `X(a, …)` is rewritten to `X_int(a, …)` when `a` is written as a **bare function-call
result** in the **first** argument position and a function named `X_int` exists. The identical
value bound to a variable first is **not** rewritten.

The trigger is the *spelling* of the argument expression, not the value, its provenance, or
anything a reader can see at the definition site. Both spellings are ordinary, both compile, and
the wrong one runs a different function body and returns a plausible value.

This is the same family as the `_str` slot, which has already caused one ecosystem-wide silent
bug: bayan's cstr+len entries were named `bayan_json_v_parse_str`, so every bare
`bayan_json_v_parse(someStr)` was rewritten into a 1-arg call to a 2-arg function and returned 0
for valid JSON, silently, across ~26 files. That was fixed consumer-side by renaming `_str` →
`_buf` in bayan 1.3.0. The difference here is that `_str` selects on the *type* of the argument,
which is at least consistent between a variable and an expression. `_int` selecting only on the
call-result spelling is not.

## Reproduction

```
fn make(): i64 { return 111; }

fn take(a): i64 { return 1; }
fn take_int(a): i64 { return 2; }

fn main(): i64 {
    var v = make();
    var via_var = take(v);        # 1 — correct
    var via_call = take(make());  # 2 — WRONG, ran take_int's body

    if (via_var == 1 && via_call == 1) { return 0; }
    return 1;
}
var r = main();
syscall(60, r);
```

```sh
$ cyrius build 2026-07-29-int-overload-call-result-misdispatch.cyr r && ./r; echo $?
compile ... OK
1                      # expected 0
```

### Observed behaviour, characterised

Each row A/B-compiled with everything else held constant, on 6.4.86:

| Call site | Routes to `X_int`? |
|---|---|
| `X(make(), …)` — bare call result, first position | **yes** |
| `var v = make(); X(v, …)` — same value via a variable | no |
| `X(111, …)` — integer literal | no |
| `X(0, make())` — call result, second position | no |
| `X(p, …)` where `p = alloc(8)` | no |

Declaring the callee to return a `Str`-shaped value changes nothing:
`fn makestr(): i64 { return str_from("s"); }` still selects `_int`, and does **not** select an
available `_str` sibling. That points at the **declared return type** driving slot selection —
and since every Cyrius function is declared `: i64`, every call result is an `_int` candidate.

## Root cause (if known)

**Speculation — I have not read the frontend.** The evidence is consistent with overload
selection consulting the *declared return type* of a callee used as an argument expression, while
a `var` binding is tracked with more specific provenance (the `alloc(8)` row does not route, so
variables clearly carry something the call result does not). If that is right, the asymmetry is
in whichever path types a call-expression argument, not in the overload table itself.

## How wide is this really

Stating the limits, because the headline overstates it:

- **Stdlib pairs did not misroute in my testing.** `str_from(sev(0))` where `sev` returns a
  C-string literal correctly produces the string, despite `str_from_int` existing. Same for the
  other pairs I could reach. So builtins appear to be resolved on a different path. **I do not
  know whether that is deliberate**, and it is the first thing worth confirming — if it is
  incidental, the blast radius is much larger than what I observed, because the stdlib ships at
  least: `println`/`println_int`, `str_from`/`str_from_int`,
  `str_builder_add`/`str_builder_add_int`, `bayan_json_get`/`bayan_json_get_int`,
  `sandhi_route_param`/`sandhi_route_param_int`, `sysfs_read`/`sysfs_read_int`.
- **It needs a consumer-defined `X`/`X_int` pair.** That is an opt-in naming choice, which is why
  this is filed as High and not Critical. But `X` plus `X_int` is a *natural* pair to write — it
  reads as "the same operation, integer variant", which is exactly what the stdlib pairs above
  are — so consumers land on it without any sense of danger.
- **Not bisected.** I did not test versions before 6.4.86.

## Why it is expensive to find

The failure is three layers from the cause and looks like a data bug, not a dispatch bug.

In agnosai, a test helper `_t_add(input, key, value)` — which builds a JSON string parameter — ran
`_t_add_int`'s body, which builds a JSON *integer*. So every string parameter was stored as a JSON
integer holding the string's own pointer. The tool under test then reported
`missing required parameter: prompt`, because its `get_str` correctly refused a non-string value.
The stored value serialised as `21854759`, which reads like a plausible id rather than a pointer.

About an hour to bisect, and only because the two helpers happened to sit next to each other in
the file. An isolated probe did **not** reproduce it — `probe(i, 0)` with `var i = 7` dispatches
correctly — so the first three attempts at a minimal repro all came back clean and pointed the
investigation at the map, at bayan, and at `str_from`'s borrow semantics before landing here.

## Proposed fix

In rough order of preference:

1. **Make the two spellings agree.** Whatever `X(v, …)` does for a variable `v`, `X(f(), …)`
   should do for a call returning the same value. This is the correct fix; it is also the one I
   am least able to scope.
2. **Warn at the definition site.** Emit a diagnostic when `X` and `X_int` are both defined and
   the overload is reachable, the way duplicate-`fn` already warns
   (`warning: duplicate fn 'path_exists' (last definition wins)`). **This alone would have been
   sufficient** — it turns an hour of bisection into a compile-time note, and it does not require
   deciding what the dispatch rule ought to be.
3. **Document the reserved suffix set.** If `_int` is intended alongside `_str`, `_ptr` and
   `_buf`, the full list and its selection rules belong in the language reference. Right now
   `_str` is discoverable only by having been bitten by it, and `_int` was not discoverable at
   all — I found it by A/B compiling names.

## Consumer-side workaround

Do not define `X` and `X_int` as siblings unless the overload is intended. Where a pair already
exists, bind the argument to a variable before the call rather than passing a bare call result.

AgnosAI has taken both: the test helpers were renamed so no suffix relationship exists
(`_t_add`/`_t_add_int` → `_t_with_str`/`_t_with_num`), and the one such pair in its own source —
`agnosai_tool_input_get` / `agnosai_tool_input_get_int` in `src/tools_native.cyr` — is dormant
because every call site passes `input` as a variable. `tests/tools_agnos.tcyr` pins that safe
spelling so a future refactor which inlines the constructor fails loudly there instead of
silently returning the wrong type.
