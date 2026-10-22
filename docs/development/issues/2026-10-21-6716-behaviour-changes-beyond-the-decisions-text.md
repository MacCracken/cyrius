# The 6.7.16 changes beyond the decisions' text — keep or restore each — OPEN

**Status:** 🟡 **OPEN** — filed 2026-10-21 at the 6.7.16 close from the release-docs pass: one drafter per lane (16 lanes)
read each lane's handoff, commits and issues against the decisions — 6.7.16's D1 – D67 (the user, 2026-10-19, at the
open), D68 – D95 (2026-10-20, at the wave-1 / wave-2 / p16-t16 integrations) and D96 – D105 (2026-10-20, at the wave-3
integration), every one answered as recommended — and marked ⚠ each change that goes past its decision's text or that
no decision covers; the drafters' discrepancy list added the rest. A sample was re-measured at
the close with 6.7.15's installed compiler (`~/.cyrius/versions/6.7.15/bin/cycc`, 2,542,240 B, its own lib/) and the
merged 6.7.16 one (main `4a3c510f3`; `build/cycc` 2,822,280 B): those items say "measured at the close"; the others quote
the lane's or the docs pass's measurement. Each change below ships in 6.7.16 and changes what an existing program does,
compiles, warns or prints in a way no decision's text names (or wider than its text). The user keeps or restores each at
the next open (the 6.7.11 – 6.7.15 precedent).
**Placement:** unplaced — keep or restore each at the next open; the user places it — never 7.x.
**Discovered:** the 6.7.16 release-docs pass (the ⚠ bullets of the sixteen lanes' behaviour drafts and the drafters'
discrepancy list), 2026-10-21.
**Kind:** decision (keep or restore, one per item).
**Severity:** Low — decisions to confirm, not defects; each change is in CHANGELOG [6.7.16] and ecosystem-migration
§ 6.7.16.

"Keep" leaves the release's behaviour as shipped; "restore" puts back what 6.7.15 did (or, where 6.7.15 compiled a shape
the release refuses, makes it compile again).

## The frontend

1. **FE-16 (372045567) — D12, user 2026-10-19:** an enum written one member per line with no `;` / `,` is refused, "expected
   ';' or ',' between enum members", as `enum E { A B }` is; the lane gave tests/tcyr/derive/derive_body_shapes.tcyr's
   newline-separated `ENl` (a shape that file tested as valid) its commas.
   - *Before → after (measured at the close):* `enum E {` / `A` / `B` / `}` then `syscall(60, B);` — 6.7.15 rc 0, exit 1;
     6.7.16 rc 1, `error:<source>:3:5: expected ';' or ',' between enum members`.
   - *Beyond the text:* D12's answer names `{ A B }` and `{ A = 1 B = 5 }` and the lint fixture only. It is the question's
     literal "no ',' or ';' between two members", and D69's reasons restate "a line break is no separator".
   - *Keep or restore:* keep — a line break is no separator in an enum; restore — a newline separates members.

2. **FE-5 (593070daa) — no decision:** `.field` (and `.m()`) on a `*T` global whose T is no struct is refused, "no struct type
   in scope for 'x'", as the local and parameter forms always were.
   - *Before → after (measured at the close):* `struct P { a; } var g = 7; var x: *i64 = &g; syscall(60, x.a);` — 6.7.15
     rc 0, exit 0 (read through the program's first struct); 6.7.16 rc 1, `4:16: no struct type in scope for 'x'`. Its
     `x.m()` under `--allow-undef` was rc 0, exit 132.
   - *Beyond the text:* outside the filed surface (a refused or unknown `*Foo`); the lane's brief called it not a
     semantics choice. It stops a program compiling; D68's reasons (2026-10-20) cite it as the precedent for the
     scalar-global band, its only acknowledgment.
   - *Keep or restore:* keep — refused at every `*T`-of-no-struct; restore — the global form compiles and reads the first
     struct.

3. **FF-49 (636939df9) — D88, user 2026-10-20:** a read `Result<..>` list refuses an argument the type-argument reader does
   not take: `Result<*Pt, i64>` ("a type argument is a type name, got '*'"), `Result<i64, Color>` ("'Color' is an enum,
   not a type argument"), `Result<i64, Option>`, `Result<u8, i64>` ("unknown type 'u8' as a type argument").
   - *Before → after (measured at the close):* `fn g(r: Result<*Pt, i64>): i64 { return 0; }` with a local `var q:
     Result<u8, i64> = 0;` — 6.7.15 rc 0, exit 7 (the list unread); 6.7.16 rc 1, `2:16: a type argument is a type name,
     got '*'`. No in-tree source writes one.
   - *Beyond the text:* D88 named an unknown name (`Result<Nope>`) and D5's third argument.
   - *Keep or restore:* keep — Result's arguments meet every type-argument refusal; restore — only an unknown name and a
     third argument are refused.

## Generics

4. **GS-5 (00d27769b) — D9, user 2026-10-19:** a trait member's `: **fn( .. )` return is refused with the `*fn( .. )` line,
   as a fn's is.
   - *Before → after (measured at the close):* `trait Sh { fn d(self): **fn(i64): i64; }` — 6.7.15 rc 0, exit 7; 6.7.16
     rc 1, "1:24: a fn-pointer type `*fn( .. )` cannot be a fn return type".
   - *Beyond the text:* D9 named `: *fn(i64): i64`.
   - *Keep or restore:* keep — every fn-pointer depth refused as a member's return; restore — `**fn` compiles there.

5. **GS-11 (4c6a024a3) — D7, user 2026-10-19:** `Name<..>` on a non-generic name is refused in positions D7 did not name — a
   trait member's return `: Pt<i64>`, its `*Pt<i64>` parameter and tuple element, a `*fn( .. )`'s own return
   `*fn(i64): Pt<i64>`, `*i32<u8>` as a field or a multi-value element, a scalar multi-value element `(i64<u8>, i64)`.
   - *Before → after (measured at the close):* `trait Sh { fn d(self): Pt<i64>; }` — 6.7.15 rc 0, exit 7; 6.7.16 rc 1,
     `2:24: 'Pt' is not a generic struct: it takes no type arguments`. `fn mv(): (i64<u8>, i64)` — 6.7.15 exit 7; 6.7.16
     `2:11: 'i64' takes no type arguments`.
   - *Beyond the text:* the lane's judgement call (a): each reader the filing named refuses its other spellings too.
   - *Keep or restore:* keep — refused in every position; restore — only D7's named positions.

6. **GS-11 / GS-12 / GS-14 (4c6a024a3, ebb53e470, b3ec1dee1) — D7, user 2026-10-19 (lint):** `cyrius lint`
   (`--syntax-only`) no longer reports a scalar return `fn f(): i64<u8>`, a by-value field `f: Pt<i64>` / `g: i64<u8>` (a
   struct's or a union's) or a slice element `[Pt<i64>]` / `[*Pt<i64>]` / `slice<*i32<u8>>`; they were lint parse errors.
   The compile refuses each at the name.
   - *Before → after (the lane's measurement):* lint rc 1 with a parse error and its cascade → lint silent; the build
     refuses before and after.
   - *Beyond the text:* D7 says nothing of lint; the lane's judgement call (b), following 6.7.15's D6 lint rule.
   - *Keep or restore:* keep — lint reads these as the compile's semantic refusals (silent); restore — lint reports them.

7. **GB-18 (1135ae069) — no decision:** in a generic's base, a parameter typed with a non-base instance takes that instance,
   so the base `Box` / a `Box<i64>` passed BY VALUE to `b: Box<Pt>` is refused, "cannot pass 'q' to a parameter of a
   different struct type".
   - *Before → after (measured at the close):* `fn rd<T>(b: Box<Pt>, k: T): i64 { return b.n; }` with `q: Box<i64>`,
     `q.n = 9`, `rd(q, 5)` — 6.7.15 rc 0, exit 9 (the base layout read); 6.7.16 rc 1, `4:63: cannot pass 'q' to a
     parameter of a different struct type in a call to 'rd'`. The pointer form `rd(&q, 5)` with `b: *Box<Pt>` (exit 9 on
     6.7.15) is refused at the release too — that one is D97's own text (the s16 lane's SZ5); at the genbind merge it
     read `Box<Pt>`'s offsets (9 → 0).
   - *Beyond the text:* the lane applied the existing different-struct rule to a signature the base had misread; no
     decision; the handoff's migration note claimed the pointer form for this bite.
   - *Keep or restore:* keep — the by-value form refused; restore — it compiles and reads the base layout.

8. **GB-19 (d2742a654) — D1, user 2026-10-19 (diagnostics):** every stub refusal — the pre-existing `.field` one included —
   names the two new shapes in its words ("`&x` of one returned as a struct, or a struct result over 8 bytes stored in
   one") and prints a `note:` naming the line that needs a struct.
   - *Before → after:* `g(5)` of a generic reading `x.b` printed the refusal without the note; it now prints
     `note: <source>:4:43: 'g' takes a field of a value typed by its type parameter` (measured at the close on the f16b
     filing's repro).
   - *Beyond the text:* D1 gave the note for its own h / g shapes. Diagnostics only.
   - *Keep or restore:* keep — every stub refusal carries the note and the wider words; restore — D1's shapes only.

9. **GB-22 (25eeba79a) — no decision:** a generic's multi-value element typed by its type parameter is the instance's
   binding, so `var t: (i64, i64) = mm2<f64>(h);`, `var t: (i64, i64) = mm2<Pt>(p);` and a generic body's `return G;` of a
   tuple global whose element types differ from an instance's are refused, as against a fn written `(f64, i64)`.
   - *Before → after (measured at the close):* `fn mm2<T>(x: T): (T, i64) { return (x, 7); }` with `var t: (i64, i64) =
     mm2<f64>(h); return t.1;` — 6.7.15 rc 0, exit 7 (t.0 the double's bits); 6.7.16 rc 1, `2:56: cannot capture 'mm2'
     into tuple (i64, i64) - it returns 2 values, (f64, i64)`. (`mm2<Pt>(p)`: exit 10 → refused, the lane's measurement.)
   - *Beyond the text:* the brief named only the newly accepted `(f64, i64)` capture; the refusals are the existing tuple
     check reading the instance's real types.
   - *Keep or restore:* keep — the capture is judged at the instance's types; restore — judged at the base's.

10. **FB-2 (2f8900ebe) — D102, user 2026-10-20:** an untyped local whose initializer is a struct CARRIER of `T` by value
    (`var y = b;` with `b: Box<T>`, `var y = mkbox(x);` returning `: Box<U>`) becomes that carrier in each instance.
    - *Before → after (measured at the close):* `fn g<T>(b: Box<T>): i64 { var y = b; return y.v.b; }` at `Box<Q>` — 6.7.15
      rc 1, `3:48: expected ';', got '.'`; 6.7.16 rc 0, exit 6. At a scalar T the generic is a stub.
    - *Beyond the text:* D102 decides "an untyped local from a T-typed value"; a `Box<T>` value is not a `T` value. Newly
      compiling only.
    - *Keep or restore:* keep — a carrier local is the carrier; restore — refused at the definition as before.

## The declaration zone

11. **ZN-5 / ZN-6 / ZN-7 (edd339932, 48409aba9, 7965f3685) — covered by 6.7.14's D29 (a) and 6.7.15's D34 (a); listed
    because the lane recorded no compiled program changing:** a zone untyped global from a generic call (or a generic
    method's generic struct result, or an explicit `.m<..>(` call's plain struct) is the instance, so `x + 1` on it
    dispatches the struct's operator fn and is refused without one.
    - *Before → after (measured at the close):* `var x = mkg1(30 + 3); var y = x + 1; syscall(60, y);` — 6.7.15 rc 0,
      exit 34 (added to the word); 6.7.16 rc 1, "undefined function 'G1_add'" and "refusing to emit binary with 1
      reachable undefined function(s)". The docs pass measured `mkg1(-3)` 254, `b.mkg(P)` 34 and `b.mk<i32>(30)` 31 →
      refused the same way.
    - *Beyond the text:* none by text (D29 (a) names the operator dispatch); the handoff said "no program that compiled
      changes", and no lane row pins the arithmetic refusal.
    - *Keep or restore:* keep — the zone global is the instance everywhere; restore — the zone arithmetic adds to the word.

12. **ZN-11 (cb004c8c8 + cbb267ab3) — D17, user 2026-10-19:** a top-level `var G: S = *GQQ;` from ANOTHER struct's `**Q` is
    refused by name.
    - *Before → after (measured at the close):* `var GQ = Q { 8, 9, 10 }; var GPQ: *Q = &GQ; var GQQ: **Q = &GPQ; var G: S
      = *GQQ; syscall(60, G.a);` — 6.7.15 rc 0, exit 8 (Q's bytes read as an S); 6.7.16 rc 1, `6:12: cannot copy '*GQQ'
      into a variable of a different struct/vector type: 'G'`. The same line in a fn has been refused since 6.7.15.
    - *Beyond the text:* D17 names the declared struct's own `**S`.
    - *Keep or restore:* keep — refused at top level as in a fn; restore — the copy of another struct's bytes compiles.

13. **ZN-11 / ZN-12 (cb004c8c8 + cbb267ab3, 62ba267ac) — D17 / D18, user 2026-10-19:** a `**S` source global, or a `P` (a `*S` global),
    declared BELOW a G over 8 B is refused by name ("cannot copy-init 'G' from a global declared below it"), where it
    compiled and SIGSEGV'd at startup (the lane's measurement).
    - *Beyond the text:* D17 / D18 name the declared struct's copy; this is the refusal a `*P` declared below already got.
    - *Keep or restore:* keep — refused; restore — it compiles (and faults at startup).

14. **ZN-12 + SS-38 (62ba267ac, d1122e9c0) — the filed shapes need none; the rest no decision:** a struct global of 8 B or
    less copied from a source a declaration below it stores at run time is refused — the filed `var A: P8 = *GP8;` / `=
    GP8;` / `= *GPP8;` (which ZN-12 had turned from "read 0" into a startup fault, and the s16 lane's SZ3 refused), and
    beyond the filed issue a whole struct global, a field chain's global or a call's value declared below.
    - *Before → after (measured at the close):* `var A: P8 = GS8;` above `var GS8 = P8 { f() };` — 6.7.15 rc 0, exit 0
      (read 0); 6.7.16 rc 1, `3:13: cannot copy-init 'A' from a global declared below it (declare the source first):
      'GS8'`. `var A: P8 = GP8;` above `var GP8: *P8 = &GS8;` — 6.7.15 exit 0 → the same refusal.
    - *Beyond the text:* the filed issue named the pointer sources; the handoff rests the rest on the guide's "declare
      the source ABOVE the copy", stated with no size limit.
    - *Keep or restore:* keep — every 8 B-or-less copy from a below-declared source refused; restore — those compile and
      read 0.

## Structs and `Str`

15. **ST-4 (918dd5e89) — D19, user 2026-10-19:** a frame's inline `Str` into a GLOBAL struct's `*Str` field (`GW.p = t`),
    through a `*W` (`pw.p = t`), in a for step, and through a `**Str` (`*pp = t`) is refused as would-dangle; each compiled.
    - *Beyond the text:* D19's answer names the local struct's field; its reason says the other shapes "come out the same
      under both options", and the refusals follow 6.7.13's D7 (1).
    - *Keep or restore:* keep — refused in every field and through every pointer; restore — only the local struct's field.

16. **ST-5 (f3331c48e) — no decision:** in a fn, an untyped `var k = x.m(..);` whose method is declared `: Str` is a `Str`
    handle, so `println(k)` / `show(k)` reach the `_str` overload (they took the untyped one; `println(k)` printed the
    header's bytes).
    - *Before → after (measured at the close):* with `fn show(x)` → 1 and `fn show_str(x: Str)` → 2, `var k = h.clone();
      return show(k);` — 6.7.15 exit 1; 6.7.16 exit 2.
    - *Beyond the text:* taken as a false refusal ("none needed"); the triage measured only `k + 1` / `k - h` / `k == h`
      (unchanged). It changes what a compiled program prints.
    - *Keep or restore:* keep — the method's `Str` result routes as `str_clone(h)`'s does; restore — the untyped overload.

17. **SS-2 (b08e5f265) — no decision:** `cyrius lint` refuses `Some(5).n = 1;` in a fn above its enum, as the build does.
    - *Beyond the text:* the issue file called the change "the user's call" (it changes what `--syntax-only` accepts); the
      build already refused the line.
    - *Keep or restore:* keep — lint agrees with the build; restore — lint accepts it.

18. **SS-8 (d77d93c9f) — D20, user 2026-10-19:** `*p` of a `*Str` into a `Str` FIELD, a literal's `Str` field or a `: Str`
    return is p, the header's address (`w.s = *p`, `GW.s = *p`, `W { *p, 1 }`, `return *p;`); it stored the header's data
    word.
    - *Beyond the text:* D20 decided a `Str` HANDLE name; the issue asked "rebind or refuse" and carries no decision line.
    - *Keep or restore:* keep — p, as into a handle; restore — the data word.

19. **SS-9 (0696846c4) — D19, user 2026-10-19:** a struct literal's `*Str` element from an inline `Str` takes its header's
    address, and a frame's `W { t, 1 }` stops compiling.
    - *Before → after (measured at the close):* `struct W { p: *Str; n; }`, `var t: Str = Str { "abcdefg", 7 }; var w = W {
      t, 1 }; return w.n;` — 6.7.15 rc 0, exit 1; 6.7.16 rc 1, `4:65: cannot store the inline Str 't' into a field - its
      header lives in this frame and would dangle (store a handle: str_new(data, len))`.
    - *Beyond the text:* D19 named the assignment `w.p = t`.
    - *Keep or restore:* keep — the literal is judged as the assignment; restore — the literal compiles (storing t's data
      word).

20. **SS-11 (f508e1f91) — D73, user 2026-10-20:** `*p` of a `*Str` into ANY `*Str` slot is p — `**qq = *p`, `*pp = *p`, `x =
    *p` into a `*Str` name, `var y: *Str = *p;`, `w.p = *p`, `WP { *p, 1 }`, `fps(*p)` into `s: *Str`, `return *p;` from a
    `: *Str` fn; each stored the data word.
    - *Beyond the text:* D73 named `*q = *p`; the other slots follow its own why (D7 (1), 6.7.15's D16, D19). Each changes
      a value.
    - *Keep or restore:* keep — p in every `*Str` slot; restore — only `*q = *p`.

21. **SS-13 (c2cd040e0) — D71, user 2026-10-20:** the store side of `*(&t)` of an inline `Str`: `*(&t) = v` is `t = v` (it
    copies the header), and `*(&t) OP= v` is refused as `t OP= v`.
    - *Before → after (measured at the close):* `var t: Str = Str { "abcdefg", 7 }; var v = str_from("xy"); *(&t) = v;
      return t.len;` — 6.7.15 exit 7 (one word written); 6.7.16 exit 2.
    - *Beyond the text:* D71's answer covered the reads and the frame's refusals.
    - *Keep or restore:* keep — the store is `t = v`; restore — one word written into t.data.

22. **SS-14 (694018b4c) — no 6.7.16 decision (6.7.15's D16 and 6.7.13's D7 (1) carried):** an inline `Str` returned from a
    fn returning `*Str` is its header's address, and a frame's `return t;` there stops compiling.
    - *Before → after (measured at the close):* `var gt: Str = Str { "abcdefg", 7 }; fn gp(): *Str { return gt; }` and
      `gp() == &gt` — 6.7.15 false (exit 2: gt's data word returned); 6.7.16 true (exit 1).
    - *Beyond the text:* 6.7.15's D16 named a `*Str` name.
    - *Keep or restore:* keep — the address, and the frame's refused; restore — the data word.

23. **SS-16 (179c315b1) — D72, user 2026-10-20:** a generic's `x: T` at T = i8 / i16 / i32 is narrowed too.
    - *Before → after (measured at the close):* `fn g<T>(x: T): i64 { return x; }`, `g<i16>(0x17FFF)` — 6.7.15 98303;
      6.7.16 32767.
    - *Beyond the text:* D72 decided a narrow parameter's own declared type. (Short of its text: a suspending `async
      fn`'s narrow parameter keeps the caller's word — filed as 2026-10-21-suspending-async-fn-narrow-parameter-holds-
      caller-word.md.)
    - *Keep or restore:* keep — a narrow T narrows; restore — the generic keeps the caller's word.

24. **SS-19 (e07b27f74) — D70, user 2026-10-20:** a narrow integer's `*(&h)` as a dyn source takes its type's impl (it was
    refused).
    - *Beyond the text:* D70 covered f64 / f32 / bool; this rests on D21 (2026-10-19).
    - *Keep or restore:* keep — newly compiles; restore — refused.

25. **SS-39r (75e50e3cf) — D87 (a), user 2026-10-20:** every other `*U` source into a struct `S` declaration is refused — a
    call or method declared `: *U`, a `*U` field, pointer arithmetic, wrapped, `callptr`, a generic instance's — named as
    spelled.
    - *Before → after (measured at the close):* `fn gq(q: *U): *U` and `var l: P3 = gq(&u); return l.x;` — 6.7.15 rc 0,
      exit 1; 6.7.16 rc 1, `4:51: cannot copy 'gq(&u)' into a variable of a different struct/vector type: 'l'` (the source
      named as spelled).
    - *Beyond the text:* D87 named a `*U` global's name.
    - *Keep or restore:* keep — every `*U` spelling refused; restore — only the global's name.

26. **SS-45 (94a79ff72) — D98, user 2026-10-20:** an untyped top-level global from an f64 call is an f64, in the zone and
    after the first statement.
    - *Before → after (measured at the close):* `fn mkf(x: f64): f64 { return x; } var Y = mkf(1.5);` and
      `f64_to(Y * 2.0)` — 6.7.15 exit 0 with "integer arithmetic with an f64 right operand"; 6.7.16 exit 3, no warning.
    - *Beyond the text:* D98 answered the zone destructure; the issue named this line as related and the unit's brief
      asked for it. `Y + 1` now does f64 arithmetic and warns.
    - *Keep or restore:* keep — an f64; restore — an untyped word.

27. **SS-46r (1fe35ed66) — D99, user 2026-10-20:** the subscript store `p[i] = mkp();` through a typed pointer to a scalar
    (`w.pi[0]`, `gi()[0]`, `GP[0]`; a generic's `p[0] = mkp();` a stub line) is refused.
    - *Before → after (measured at the close):* `var p: *i64 = &x; p[0] = mkp(); return x;` — 6.7.15 rc 0, exit 77;
      6.7.16 rc 1, `3:54: cannot assign 'p[0]: i64' from 'mkp', which returns the struct 'Q' - store it through a '*Q' or
      bind a field`.
    - *Beyond the text:* D99 named `*p`; the subscript is the same store as `*(p + i)`.
    - *Keep or restore:* keep — refused; restore — the first word stored.

## Receives and vectors

28. **RV-1 (9a58ad376) — no decision (words):** a tuple parameter's comparison / `!x` / `&&` / `||` argument is "a bool".
    - *Beyond the text:* the issue's fix direction asked for "one line to the user when placed", D36's words being decided
      text; the lane took the default. Refused before and after.
    - *Keep or restore:* keep — "a bool"; restore — the earlier words.

29. **RV-2 / RV-2r (7a3186753, b45799db7) — D23, user 2026-10-19 (words):** a float-bearing argument the compiler types integer
    gets "cannot pass an integer …" — `take(1.5 & 1)`, `take(1.5 +| 1)`, `take(-!1.5)`.
    - *Beyond the text:* D23 gives only the f64 and bool words. Every such argument is refused either way.
    - *Keep or restore:* keep — the integer words; restore — the f64 words for any float-bearing argument.

30. **RV-5r (0b2446c31) — D26 / D24, user 2026-10-19 (D100 since):** a vector call behind leading parentheses that close
    after an operator starts the source and is refused: `var x: i64 = (mk2(41, 7) + 1) * 2;`, `x = ..`, `G = ..`, and the
    untyped / top-level `var w = (mk2(..) + 1) * 2;`.
    - *Before → after (measured at the close):* 6.7.15 rc 0, exit 2 (the first word; 84 on cx); 6.7.16 rc 1, `2:29: vector
      return type does not match the declared type`.
    - *Beyond the text:* D26's question named parentheses around the call alone; D100 (2026-10-20: "wherever it sits")
      covers it, answered after the commit.
    - *Keep or restore:* keep — D100 decides it now; restore — compiles with the first word, against D100's text.

31. **RV-6 / RV-7 (f774e5c50, 2e478b6e4) — no decision (6.7.11's value-form rule; D24's premise):** an operator after a vector
    call at a vector local, and `return mk2(41, 7) + 1;` from a vector-returning fn, stop compiling.
    - *Before → after (measured at the close):* `var w: f64v2 = mk2(41, 7) + 1; return load64(&w);` — 6.7.15 rc 0, exit 41
      (the `+ 1` dropped; the lane: 161 on x86_64 / aarch64 for the filed row, 165 on cx, a parse error on PE); 6.7.16
      rc 1, "a value-form vector local is initialised only from … - got `mk2`".
    - *Beyond the text:* D24's text calls this line "already" refused; it compiled. The lane refused it under 6.7.11's
      rule (a value-form vector local takes a vector, or nothing) and the 6.6.6 return rule, with no decision.
    - *Keep or restore:* keep — refused (there is no vector `+`); restore — compiles with the per-target value.

32. **SS-49 (d874a1ec5) — D101, user 2026-10-20:** a whole vector call is refused also into an `f64` / `f32` parameter
    (`tf(mk2(..))`), as a builtin's or an indirect call's argument (`syscall(60, mk2(..))`, `store64(&x, mk2(..))`,
    `fncall1(f, mk2(..))`) and as a closure's expression body (`|k| mk2(k, 7)`).
    - *Before → after (measured at the close):* `fn tf(x: f64): i64 { return 3; }` and `return tf(mk2(41, 7));` — 6.7.15
      rc 0, exit 3; 6.7.16 rc 1, `3:28: a vector value cannot be passed to an f64 parameter - 'mk2' returns a vector,
      passed to parameter 'x' of 'tf'`.
    - *Beyond the text:* D101 named a scalar fn's return and an integer / untyped parameter.
    - *Keep or restore:* keep — every word slot; restore — only D101's named slots.

## Method chains

33. **SB-1 and its review fixes (7cdce3aa1; cd9d77e02, 37bde68f1, d21d3a9bb) — no decision (the single name's rules, v6.6.16's
    C4):** a `: stack` pair method on a chain bound, assigned or stored one-wide is refused "bind both" on the non-field
    heads and the generic steps / heads too — `(*pw).p.rs(3)`, `mk().p.rs(3)`, `callptr(&gw, &w).p.rs(3)`,
    `w.p.idv(q).rs(3)`, `w.gpx(&w).p.rs(3)`; each kept the tag.
    - *Beyond the text:* the filed issue names a FIELD chain (`w.p.m2()`); the other heads are the same root cause.
    - *Keep or restore:* keep — every chain head is the single name; restore — only field chains.

34. **SB-1 (forwarders) — no decision (v6.6.16's C4; 6.7.14's RC-15 / RC-22):** `var v = fwd(w);` above a `fwd` defined
    below that forwards a chain's pair (`return w.p.rs(3);`, `w.p.rs(3)?`, `return gw(2).p.rs(3);`, …) is refused "bind
    both"; the caller read the tag.
    - *Beyond the text:* the filed issue names the destructure, `?`, the lossy binds and tuple capture, not forwarders.
    - *Keep or restore:* keep — refused; restore — the caller reads the tag.

35. **SB-1r4 (891683647) — D42, user 2026-10-19:** a single name's explicit generic `p.rg<i64>(5)?` as a fn's only pair route
    makes that fn a pair to a caller above it.
    - *Before → after (measured at the close):* `var v = fwd(w);` above `fn fwd(w: W): i64 { var p: P = w.p; var v =
      p.rg<i64>(5)?; return v + 0; }` — 6.7.15 rc 0 (fwd's mixed-return warning), exit 6; 6.7.16 rc 1, "a `: stack` enum
      returns two values — bind both".
    - *Beyond the text:* within D42 ("both spellings compile, refuse and run alike"), beyond the filed issue's text (a
      single name, not a chain).
    - *Keep or restore:* keep — the explicit spelling as the inferred; restore — the caller reads 6 / the tag.

36. **SB-1 (multi-value into a field / a small-struct or async return) — no decision (6.7.11's and 6.7.15's GN-21
    refusals):** `hh.s = w.p.m2();`, `hh.s = (*pw).p.m2();`, `return w.p.m2();` from a `: Q8` fn or an `async fn` stop
    compiling; each stored or returned the first value.
    - *Beyond the text:* the filed issue's acceptance text names the destructure, `?`, the lossy binds and tuple capture.
    - *Keep or restore:* keep — refused as on a single name; restore — the first value.

37. **SB-2 (df29930ab) — no decision (every other head's refusal):** a multi-value method on a `callptr(&f, ..)` chain passed
    into a by-value struct or tuple parameter is refused ("a multi-value call 'm2' is not a struct 'Q16' argument …"); it
    compiled and crashed on every target.
    - *Beyond the text:* met while landing the issue.
    - *Keep or restore:* keep — refused; restore — compiles (and crashes).

## Platform

38. **PP-2r (9ef802604) — D80, user 2026-10-20:** on Windows, `sys_ftruncate` of a device such as `NUL`, and
    `sys_truncate("NUL", n)`, answer -22 (they answered -1 on real Windows, -9 under wine); any ftruncate step whose Win32
    failure the table leaves unmapped (-1) reads -22, and SetEndOfFile's -9 after both seeks accepted the fd reads -22.
    - *Beyond the text:* D80 names a pipe, a console, a read-only and an O_APPEND descriptor; the -1 → -22 map covers
      every unmapped Win32 code, and the by-path answer comes from a lib-side map, not "through the Windows error table"
      (D79's words).
    - *Keep or restore:* keep — -22 for every unmapped ftruncate failure; restore — the table's -1 outside D80's cells.

39. **PP-2 (990610948) — D79, user 2026-10-20:** the raw `syscall(0xF03F, h)` (SetEndOfFile) reroute answers 0 / -errno
    instead of the BOOL, so a raw caller's nonzero-is-success test inverts. The three in-tree callers flipped in the same
    commit.
    - *Beyond the text:* D79 names mkdir / unlink / rmdir / ftruncate / truncate, not the raw reroute's contract.
    - *Keep or restore:* keep — 0 / -errno; restore — the BOOL.

40. **PP-9 (92d50a875) — D83, user 2026-10-20:** the native TLS 1.3 server refuses an EMPTY compression_methods list with
    decode_error (the 1.2 parse's P6 answer); the 1.3 parse skipped it unread and negotiated.
    - *Beyond the text:* D83 says a 1.3 list "anything other than the single null method" gets illegal_parameter — read
      literally, an empty list falls under that alert; the lane classed it under "lists that do not frame keep D32's
      decode_error".
    - *Keep or restore:* keep — decode_error; restore (to the text) — illegal_parameter (alert 47).

41. **PW-1 / PW-2 (ebbe09d0b, 141f80a2b) — no decision:** on Windows an fd above 2 with a low bit set answers -9 before any
    Win32 call in every fd reroute (close, read, write, seek, fsync / fdatasync, ftruncate), and the stdlib's socket, lock
    and final-path wrappers answer -9 for it (`sock_send` / `sock_recv` give `Err(9)`; `win_handle_under` -1).
    - *Before → after (the lane's measurement):* the NT kernel ignores a handle's two low bits: `sys_close(h + 3)` answered
      0 and closed `h`, a write landed in `h`'s file, `sock_close(s + 3)` closed `s`. The filed alias.cyr printed
      `52 0 -9 -9` under wine and prints `52 -9 3 0` (Linux `3 -9 3 0`).
    - *Beyond the text:* the filing called this change the user's call ("beyond D78"); the PW1 brief ruled no decision was
      needed and no D-id was asked.
    - *Keep or restore:* keep — -9 for an fd cyrius never handed out; restore — the alias acts on the handle below.

42. **PW-3 (2cd5ab993; review fix eac5f88cf) — D94, user 2026-10-20:** a raw `syscall(0xF03E, ..)` (CreateSymbolicLinkW)
    answers 0 for a made link and a negative errno for a failure; it answered the BOOLEAN (1 made, 0 failed), so a `!= 0`
    success test reads the wrong way round.
    - *Beyond the text:* D94 names the three calls' failure errnos, not the raw reroute's success value (the p16 lane's raw
      0xF03F did the same under D79, item 39).
    - *Keep or restore:* keep — 0 / -errno; restore — the BOOLEAN.

43. **PW-4 (b67ed7b83) — D95, user 2026-10-20:** `file_open` / `sys_open` of a directory under `O_CREAT|O_EXCL` answers -17
    (EEXIST); real Windows answered -13 (wine already -17).
    - *Beyond the text:* D95 names -21; -17 is Linux's answer and the `file_create_exclusive` answer (6.7.14) D95 cites as
      its model.
    - *Keep or restore:* keep — -17; restore (to the text) — -21.

44. **PL-10 (07065368d) — no decision of its own (6.7.12's D9 direction; ordered after D51):** a 16-byte disallowed-CTL entry
    is applied under both readings, the public-key MD5 and an MD2 / MD5-signed certificate's signature hash, and a trust
    policy holding ONLY 16-byte deny keys now parses each certificate's signatureAlgorithm — an unreadable shape answers 2
    (distrusted).
    - *Before → after (the lane's measurement):* latent and fail-closed; no change on cass (its CTL holds 48-byte entries);
      tls_system_trust_store.tcyr 274 → 301 rows on cass.
    - *Beyond the text:* D51 kept PL-14's every-length reading for the 20 / 32 / 64-byte lengths; the 16-byte double
      reading and the deny-keys-only parse have no decision.
    - *Keep or restore:* keep — both readings, fail-closed; restore — 16 bytes read as a public-key MD5 only.

## Tools

45. **TL-10 / TL-10r (87cd284ac, 9cd9b8442) — no decision (the guide's `--syntax-only` contract):** `cycc_cx --syntax-only`
    exits with the parse's status — a call to another file's fn is a warning alone (rc 0; it was the "undefined
    function(s) called (cx backend)" refusal, rc 1) — and it accepts a REACHABLE undefined call under the flag, which the
    native compilers refuse.
    - *Beyond the text:* the reachable-call divergence is the triage's known one, stated in the guide; no decision asked.
    - *Keep or restore:* keep — cx's lint accepts it; restore — refused under the flag as natively.

46. **TL-11 (07b9a4130) — 6.7.14's D59, user 2026-10-16:** the macOS and Windows tarballs are built from cyrius.cyml's
    `[release] bins`: macOS newly ships cyrius-lsp, ark, cyrld, ts_test_runner and cyrsign-efi, and its `bin/cyriusly` is
    the compiled version manager (the shell script moves to `versions/<v>/scripts/cyriusly`); Windows newly ships ark,
    cyrld, cyriusly, ts_test_runner and cyrsign-efi `.exe` (the Windows `cyriusly.exe` then decided by D84).
    - *Beyond the text:* D59 ("Ship every [release] bin, built for aarch64") named the aarch64 tarball; applied from the
      issue's fix direction with no decision asked (the issue and scripts/release-bins.sh misquote D59 as "the manifest's
      [release] bins list is the source of truth for every tarball").
    - *Keep or restore:* keep — every tarball ships the manifest's bins; restore — the macOS / Windows lists of 6.7.15
      (the shell `cyriusly` on macOS).

47. **TL-15 / TL-15r (7eb1197ea, cf2b34ef1) — the fragment issue's decision, user 2026-10-19 ("the design's defaults
    stand"):** cyrius-lsp checks each project file through its compile unit; its lib/ peer rule is the stdlib gate's
    (lib/<R>_<x>.cyr, R's family includes it, no Usage line of its own, no distlib marker), and it drops an inherited
    `CYRIUS_TARGET_*` / `CYRIUS_MACHO*` from a project child's environment.
    - *Beyond the text:* the design's parenthetical was "its Usage names itself, or no lib/ file includes it"; the
      environment drop is not in the design.
    - *Keep or restore:* keep — the stdlib gate's peer rule and the clean child environment; restore — the design's
      parenthetical, the inherited environment.

48. **TL-15r2 (65ac12b59) — the same decision:** this repo's `[lsp] skip` names src/main_aarch64_native.cyr beside
    bootstrap/cybs.cyr.
    - *Beyond the text:* the decision text named `[lsp] skip = ["bootstrap/cybs.cyr"]`; this repo's manifest only.
    - *Keep or restore:* keep — both skipped; restore — cybs.cyr alone.

49. **TT-12 / TT-12r (d0a305989, 9468d291c) — D84, user 2026-10-20:** besides refusing its POSIX verbs by name, the Windows
    `cyriusly.exe`'s KEPT verbs' hints name install.ps1 (an empty store's `list`, `use <v>` of a version not installed,
    `use <v>` outside a project, `uninstall` of the active version), `--help` gains a two-line Windows note, and
    `uninstall <v>` of a version not installed answers "Version <v> not installed.", rc 0, before D84's refusal.
    - *Beyond the text:* D84 says the kept verbs "keep working".
    - *Keep or restore:* keep — the hints name install.ps1; restore — the 6.7.15 hints (`cyriusly install`, `--global`).

50. **TT-14 (a61a55558) — no decision (D84: `list` / `version` keep working):** the Windows `cyriusly.exe` with no
    `CYRIUS_HOME` reads `%USERPROFILE%\.cyrius` (it read `HOME`), and `which` prints `<home>\bin\cycc.exe`.
    - *Beyond the text:* where `HOME` IS set (an ssh session, a POSIX shell) and `CYRIUS_HOME` is not, the home moves from
      `$HOME/.cyrius` to `%USERPROFILE%\.cyrius`, and `which`'s output changes.
    - *Keep or restore:* keep — `%USERPROFILE%` on Windows; restore — `HOME` when set.

## Recorded, not behaviour changes (no program computes differently)

- **PP-17 – PP-19 (fc0ed89ba, ee45a5d87, 3c6730c42) — D75, user 2026-10-20 (tests only):** D75 promised one "no system
  roots" line per system-set group under wine; 42 of the 77 wine failures are memory-store policy rows (wine's crypt32
  refuses certificate properties 84 / 104 / 122 / 126 / 127), so tls_system_trust_store also prints 42 not-run lines and
  one planted-bundle line, and the lane-gate fixes carry D75's shape to three files D75 does not name (PP-19 skips a cx
  row on a measured property).
- **The libfix lanes' implementation choices — no decision, no semantics:** the cbt helpers in cbt/core.cyr carry no
  `#ifndef CYRIUS_TARGET_WIN` guard; a both-streams fd is closed when it is neither 1 nor 2; the tests run
  `ssh -GF/dev/null`; check_driver axis 22 falls back to an unprivileged user namespace; LF-5's parent-side lift goes past
  the plan's literal text.
- **TT-2 (956e41e44) — no decision (the issue: none needed):** the lsp gate's F8 assertion changed — a fragment whose own
  error was fixed, while src/main.cyr keeps its own, shows the unit note instead of `[]`; the note is new in 6.7.16 (the
  tools lane's TL-15), so nothing changes against 6.7.15.
