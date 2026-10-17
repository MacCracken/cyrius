# A fn-local `var h: S = gpg<S>();` — a handle from a GENERIC call declared `: *T` — drops its `S` annotation: `h` is an untyped word and `h.v` is refused "no struct type in scope for 'h'" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 struct lane's tree (`l6711-struct`, `bcca83f9`) and on
`42a0b63a` (before the lane's unit S2), x86_64: the generic row is refused; the non-generic `fn gp(): *S` row exits 68
(a handle bound to `GS`, as the handle line says a `*T` call is); a top-level `var G: S = gpg<S>();` and a fn-local
`var h: *S = gpg<S>();` both work (8).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (generics lane, wave 1, unit G2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 struct lane (unit S2), probing the positions of
issues/archived/2026-10-13-generic-pointer-returning-call-as-struct-source.md. That issue (fixed in S2) made a generic `: *T`
call a struct SOURCE (copies, dereferences, `gpg<S>().v`); the handle BINDING of an annotated fn-local is a different
path (PARSE_VAR's struct-receive lookahead) and was not in its filed surface.
**Severity:** Medium — a loud refusal at the first `h.f`; but a use that does not name a field (`take(h)`, `h + 1`,
`var c: S = h;`) gets an untyped word where the annotation said `S`.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
for body in 'fn gp(): *S { return &GS; }\nfn f(): i64 { var h: S = gp(); h.v = 6; return GS.v * 10 + h.w; }' \
            'fn gpg<T>(): *T { return &GS; }\nfn f(): i64 { var h: S = gpg<S>(); h.v = 6; return GS.v * 10 + h.w; }' \
            'fn gpg<T>(): *T { return &GS; }\nfn f(): i64 { var h: *S = gpg<S>(); return h.w; }'; do
  printf "struct S { v; w; }\nvar GS = S { 5, 8 };\n$body\nsyscall(60, f());\n" > /tmp/gh.cyr
  if build/cycc < /tmp/gh.cyr > /tmp/gh 2>/tmp/gh.err; then chmod +x /tmp/gh; /tmp/gh; echo "exit $?"
  else grep -m1 '^error' /tmp/gh.err; fi
done
```

Measured: `exit 68` (non-generic: `h` a handle to `GS`, `h.v = 6` reached it); `error:<source>:4:42: no struct type in
scope for 'h'; a '.field' assignment needs its struct declaration (missing include?)`; `exit 8` (control). Expected
for the second row: 68, as the non-generic call gives.

## Root cause

PARSE_VAR's struct-receive lookahead (`src/frontend/parse_decl.cyr`, the `_look_fi = _gen_resolve_call(..)` block,
"v6.3.39 (B-explicit)"): for a GENERIC callee (`GFTP != 0`) with an annotation (`pscale < 0`) it resets `pscale = 0`
whenever `_gen_decl_check(S, pscale, _look_fi) == 0`, so a struct-VALUE return re-derives its receive from the base.
`_gen_decl_check` answers 0 for a callee whose `GFRS <= 0` — a `: *T` return records `GFRS = -8` — so the annotation of
a `*T` receive is dropped as well, and the local is declared untyped. Measured: guarding the reset on `GFRS(S,
_look_fi) > 0` (a scratch copy) makes the row exit 68. PARSE_VAR is at cybs's per-fn reference ceiling; the guard
belongs in a helper.

## Consumer-side workaround

Annotate the local as a pointer (`var h: *S = gpg<S>();` — fields work through it), or bind the handle from a
non-generic call.
