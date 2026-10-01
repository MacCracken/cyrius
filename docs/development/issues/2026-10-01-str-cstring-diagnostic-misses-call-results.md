# The Str → `: cstring` diagnostic types only a named local, and its `str_data` hint is wrong

**Status:** 🟡 **OPEN** — filed from bayan 1.5.10. Measured 2026-10-01 against the cyrius
**6.6.12 release** toolchain, x86_64 and `--aarch64` (run under qemu-aarch64), with
`repros/2026-10-01-str-cstring-diagnostic-misses-call-results.cyr`: warnings and run output
byte-identical on both targets.
**Placement:** **6.6.13**, bite I11 (2026-10-01, with the other open issues; this filing had put it in the
backlog) — see `roadmap.md` § 6.6.13. The *Related* `#deprecated` gaps are a separate defect, recorded in
roadmap.md's Potential backlog.
**Discovered:** 2026-10-01, bayan 1.5.10 (re-measuring the diagnostic bayan 1.4.1 armed by
annotating `bayan_json_v_obj_get(v, key: cstring)`).
**Severity:** Low — missing warnings and a misleading one; the code generated is right. The code
the check fails to flag is not: a `Str` passed where a `char*` is read is a silent wrong answer,
and the crash, if any, comes later and somewhere else.
**Affects:** cyrius 6.6.12 (measured; earlier versions not measured — the gating dates from
v5.10.24, per the comment at `parse_fn.cyr:3164`). Source read, read-only, from the cyrius tree at
VERSION 6.6.12: `src/frontend/parse_fn.cyr` — PARSE_FNCALL's Str check :3163–3197, PARSE_RETURN's
tail-call argument loop :742–783, `_call_arg_one` :1735; `src/frontend/parse_decl.cyr` —
PARSE_GVAR_REG's global typing :2719–2752.

## Summary

A parameter annotated `: cstring` arms the warning
`passing Str-typed 'x' to 'f' which expects a cstring`. It fires only when the argument's FIRST
token is an identifier that resolves to a `Str`-typed local or parameter, and only on
PARSE_FNCALL's path. Everything else that hands the callee a `Str` compiles with no diagnostic —
including the most natural spelling, `f(o, str_from("k"))`.

Where it does fire, it misdirects:

- **The hint is wrong for a `: cstring` parameter.** It says `use str_data(x) for raw bytes`. A
  `Str` is not NUL-terminated at its length — `str_sub`, `str_split` and `str_new` borrow their
  parent's bytes — so `strlen(str_data(x))` can run past the string and a lookup can match a
  LONGER key. And `str_data(..)` is a call, which the check cannot type, so taking the hint turns
  a warned bug into a silent one (F2 below).
- **On `s.data` the warning is right and its text is not.** The check types the base identifier,
  so `f(o, s.data)` reports "passing Str-typed 's'" although what is passed is the data pointer.
  Warning there is correct — that pointer is not NUL-terminated at `str_len(s)` either (F1 below
  answers another key's value) — but the message describes the wrong thing and its hint suggests
  the same mistake.

## Reproduction

`repros/2026-10-01-str-cstring-diagnostic-misses-call-results.cyr` (stdlib only).
`lookup(t, key: cstring)` answers 1 for the key `"name"`, 2 for `"names"`, 0 otherwise. Every call
means `"name"`, so the right answer is always 1. The exit code is the number of W/F calls that did
not answer 1.

```sh
# from the repository root; writes ./r
cyrius build docs/development/issues/repros/2026-10-01-str-cstring-diagnostic-misses-call-results.cyr r
./r; echo "exit=$?"
```

| | line | what `key: cstring` is handed | warns | answer |
|---|---|---|---|---|
| W1 | :69 | named `Str` local `sk` | yes | 0 |
| W2 | :70 | `str_from("name")` | no | 0 |
| W3 | :71 | `mk()`, a fn declared `: Str` | no | 0 |
| W4 | :72 | global declared `var gs: Str = str_from(..)` | no | 0 |
| W5 | :73 | inferred global `var gi = str_from(..)` | no | 0 |
| W6 | :74 | `: Str` struct field, `h.name` | no | 0 |
| W7 | :75 | tail call `return lookup(t, sk)`, `sk` a `Str` local ¹ | no | 0 |
| W8 | :76 | tail call `return lookup(t, ps)`, `ps: Str` param | no | 0 |
| W9 | :77 | method call `o.lk(sk)` into `fn T_lk(self, key: cstring)` | no | 0 |
| F1 | :78 | `sl.data`, `sl = str_sub(str_from("names"), 0, 4)` | yes, as "Str-typed 'sl'" | **2** |
| F2 | :79 | `str_data(sl)` — what the F1 hint says to write | no | **2** |
| C1 | :80 | `str_cstr(sl)` (a NUL-terminated copy) | no | 1 |
| C2 | :81 | the literal `"name"` | no | 1 |

¹ A tail call is diverted to PARSE_FNCALL — and so gets the check — only when its argument list
also contains an integer literal (`_tc_args_divert`, :680): measured, `return lookup(0, sk)`
warns; `return lookup(t, sk)` (W7) does not.

Expected: a warning on W1–W9, F1 and F2, each hinting at a `Str`-typed sibling or `str_cstr(..)`.
Actual, 6.6.12 release, x86_64, exactly as printed by the two commands above:

```
compile docs/development/issues/repros/2026-10-01-str-cstring-diagnostic-misses-call-results.cyr -> r [x86_64] warning:<source>:69:38: passing Str-typed 'sk' to 'lookup' which expects a cstring
  hint: use str_data(sk) for raw bytes, str_println(sk) for printing, or annotate the param `: Str`
warning:<source>:78:38: passing Str-typed 'sl' to 'lookup' which expects a cstring
  hint: use str_data(sl) for raw bytes, str_println(sl) for printing, or annotate the param `: Str`
note: 288 unreachable fns (50319 bytes — set CYRIUS_DCE=1 to eliminate, CYRIUS_DCE_VERBOSE=1 to list)
OK (68568 bytes)
W1 0
W2 0
W3 0
W4 0
W5 0
W6 0
W7 0
W8 0
W9 0
F1 2
F2 2
C1 1
C2 1
exit=11
```

`--aarch64` (the binary run under qemu-aarch64) prints the same two warnings and hints, the same
thirteen lines and `exit=11`; only the `compile` line's target and the byte counts differ.

## Root cause

Measured shapes, read against the source (line numbers from the tree at VERSION 6.6.12):

- **The check looks at one token.** `parse_fn.cyr:3163` gates on `PEEKT(S) == 2` and types
  `PEEKV(S)` — the argument's first identifier — through `FINDLOCAL` / `FINDVAR`. It never looks
  at the token after it, so:
  - `IDENT (` — a call (W2, W3, F2). The name is a function, both lookups miss, the type stays 0:
    silent. **The overload dispatcher about 420 lines above, in the same PARSE_FNCALL**
    (:2744–2750: `TOKTYP(S, GTI(S) + 1) == 10` → `FINDFN` → `GFRS`, the declared return struct id),
    already resolves exactly this shape; that is how `ca(str_from("k"), 0)` reroutes to a `ca_str`
    sibling today (measured on the release: it calls `ca_str`, while `ca("k", 0)` calls `ca`). The
    type check does not ask the same question.
  - `IDENT .` — a field (W6, F1). The BASE identifier is typed, not the field: a struct local's
    `: Str` field is silent, and a `Str` local's `.data` is reported as the `Str` itself.
- **Globals never match.** The `FINDVAR` arm compares `GVTYPE` against the LOCAL encoding
  `0 - sid` (:3186). A global declared `: Str` records a POSITIVE struct id
  (`parse_decl.cyr:2749`, `SVTYPE(S, vcnt, ann_sid)`), so W4 misses on the sign. An inferred global
  records no type at all: PARSE_GVAR_REG writes `SVTYPE` only for a struct-literal initializer or
  an annotation (:2719–2752; `psc` is set only by a pointer annotation, :2570), and
  `var gi = str_from(..)` has neither. Correcting the sign alone therefore leaves W5 silent.
- **The tail path has no Str check.** PARSE_RETURN's own argument loop (:742–783) runs the SIMD
  class check and, after the call, `_DEPRECATED_WARN` (:790), but not this; it reaches
  PARSE_FNCALL only via the literal divert (¹). W7, W8.
- **The method path has no Str check.** `_call_arg_one` (:1735) runs
  `_check_int_lit_cstring_arg` — shared into it in 6.6.5 because "`w.pr(42)` into a `: cstring` param compiled
  clean and SIGSEGV'd where the identical free fn was a hard error" (parse_fn.cyr:3160) — but not
  the Str check. W9.
- **The hint is fixed text** (:3193–3197), and its first suggestion is F2.

## Proposed fix

The 6.6.5 move once more: extract the Str check into one helper and call it from all three
argument loops (PARSE_FNCALL, `_call_arg_one`, the tail loop). Inside it, type the argument only
when it is a single primary that ends at `,` or `)`:

- `IDENT` — a local or parameter (as now), or a global: compare a declared global's positive
  struct id, and give an inferred global a type at registration (the initializer callee's `GFRS`
  for `var g = f(..)`) — without that, W5 stays silent;
- `IDENT ( … )` — the callee's `GFRS`, as the dispatcher at :2744 already computes (W2, W3);
- `IDENT . field` — the field's declared type (W6). For a `Str`'s own `data` field (F1) keep
  warning, warn on `str_data(x)`, its accessor (F2), as well, and in both say what is wrong: the
  data pointer of a `Str` is not NUL-terminated at its length.

In every case the hint should name a `Str`-typed sibling of the callee if one exists,
`str_cstr(x)` for a NUL-terminated copy, or annotating the parameter `: Str` — never `str_data(x)`.
Anything else (`s + 8`, `load64(p)`, an index) is left alone. Warning text only — no codegen
change, so every existing binary stays byte-identical.

## Consumer-side workaround

bayan 1.5.10 makes the caller state the key type in the NAME:
`bayan_json_v_obj_get_by_cstr(v, key: cstring)` (new) and `bayan_json_v_obj_get_by_str(v,
key: Str)` (1.4.1), and marks the bare `bayan_json_v_obj_get` and its alias `json_v_obj_get`
`#deprecated(..)`. A deprecation warns at the call site whatever the argument is, so it reaches
the W2 spelling this check cannot see; behaviour is unchanged (both forward to `_by_cstr`).
`_by_cstr` itself has exactly this check's reach until this issue is fixed.

## Related: `#deprecated` gaps (measured on the 6.6.12 release; separate filing suggested)

- **Silent:** a call through `&f` (`fncall1(&old_f, 1)`); a method-dot call `o.m()` whose `T_m`
  is `#deprecated`; a call the compiler parses before the deprecated definition.
- **Mislocated on a tail call:** PARSE_RETURN warns (`_DEPRECATED_WARN(S, tcfi, tcnoff)`, :790)
  after the call's `)` and `;` are consumed (:781–785), so the warning carries the NEXT token's
  position — the next line or later. Measured: `return old_f(x);` on line 10 with `}` on line 11 is reported at
  `<source>:11:1`; the same call on line 14 followed by two blank lines and `}` at 17 is reported
  at `<source>:17:1`. A non-tail `var r = old_f(1);` on line 20 is reported correctly, at
  `<source>:20:19`. A reader following the line number lands on the wrong line.
