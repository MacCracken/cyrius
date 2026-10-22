#!/bin/sh
# Gate: an INLINE `Str` is its header's address wherever a `Str` value is taken (6.7.13, the user's
# decision D7 (1), 2026-10-15; issues/archived/2026-10-12-inline-str-local-passed-to-str-param-wrong-value.md).
#
# THE DEFECT (measured on the 6.7.13 structs lane before the fix, 44ab2052, x86_64 / aarch64 under qemu /
# cx under cxvm / PE under wine, all four equal): a `Str` is a heap handle by name — its slot holds the
# address of a 16-byte `{ data; len; }` header — but `var t: Str = Str { "abcdefg", 7 };` is an INLINE
# header on the frame, whose slot is field 0. Every use of the bare name as a `Str` value took
# that slot, the `data` word, as the header, with no diagnostic:
#     f(t), f((t)), str_len(t) with `fn f(s: Str)`        -> 0 (the filed repro), want 7
#     f(30, t) with `fn f(k, s: Str)`                     -> 30, want 37
#     f(gt), gt an inline global                          -> 0
#     var h: Str = t; / var h = t; then f(h)              -> 0
#     h = t into a handle (`var h = str_from("zz")`)      -> 122 (the byte after "abcdefg"'s NUL)
#     return t; from `fn mk(): Str`                       -> 0 (and t dies with the frame)
#     G = t / w.s = t / W { t, 1 } / *ps = t              -> the data word stored as the header
#
# THE RULE (the user's decision D7 (1)): the bare name of an inline `Str` is its header's address wherever a
# `Str` value is taken — a `Str` or `*Str` parameter (any argument loop: a call, a method's argument, a tail call), a
# `Str` declaration (`var h: Str = t;`, and `var h = t;` as D29 types it: h is a second handle to t's header,
# no copy), an assignment into a `Str` handle (`h = t` rebinds h) — with no allocation: `&t` for a local, the
# static address for an inline global, the environment copy's address for a closure's capture (6.6.5). The
# uses that would let a FRAME's header outlive the frame are refused by name, at the name:
#     cannot return the inline Str 't' from a fn returning Str - its header lives in this frame and would
#       dangle (return a handle: str_new(data, len))
#     cannot store the inline Str 't' into a global / into a field / through a pointer - ... (store a handle: ...)
# A global's address is static and a capture is a copy in the closure's environment, so neither is refused
# (a closure returned out of t's frame keeps its copy: K4); a `defer` runs in the frame. A position that takes
# no `Str` value (an untyped parameter, store or fn return) keeps the word (K5, K6).
#
# 6.7.14 (the user's decision D20 (a), 2026-10-16; issues/archived/2026-10-15-str-handle-into-inline-str-stores-one-word.md):
# `t = a` with t an inline `Str` and a a `Str` HANDLE — a local, a parameter, a global, a call or method declared
# `: Str`, a `Str` field — copies the 16-byte header a points at, as `t = u` between inline `Str`s does; through
# 6.7.13 it stored a's address into t.data and left t.len stale (6.6.16's pun: `var t: Str; t = a; return t.len;`
# read the frame's old bytes). So a bare `var t: Str;` (no initialiser) joins D7 (1): `f(t)` passes its header
# and `return t;` from a fn returning `Str` is refused (X3, restored), where 6.7.13's review fix had kept it
# outside the decision (its bare name its first word). An untyped source keeps the one-word store (K8).
#
# 6.7.14 (the user's decision D23 (b), 2026-10-16; issues/2026-10-16-inline-str-header-escapes-through-bound-
# handle.md): the refusals stay by name — a handle bound to a frame's t (`var h: Str = t; return h;`, `G = h`) is
# `&t` and dangles as `var p = &t; return p;` does; the guide says so, and D23a pins that it compiles clean.
#
# 6.7.14 (the user's decision D18 (c), 2026-10-16; issues/2026-10-15-inline-str-into-untyped-or-other-pointer-
# position-passes-data-word.md): only where a type says `Str`. lib/str.cyr types the `Str` methods' operand —
# `Str_eq` / `Str_cat` `other`, `Str_contains` `needle`, `Str_starts_with` `prefix`, `Str_ends_with` `suffix` —
# `Str`, so `h.eq(t)` passes t's header (D18a, the filed repro: 1, was 0) and a string literal argument is passed
# as a `Str` (`h.eq("abc")` 1, was 0); a handle argument compiles byte-identical to the untyped methods (CMP). `var
# p: *Str = t;` takes the header as a `p: *Str` parameter does (the crossos q_* rows). fncallN, callptr, a vec, a
# tuple element and an untyped if-expression branch keep the word (K9).
#
# 6.7.14 (the user's decisions D21 (a) and D22 (b), 2026-10-16; issues/2026-10-15-top-level-str-declaration-from-
# inline-str-global-copies.md): a top-level `var H: Str = gt;` (gt an inline `Str` global) binds a handle global to
# gt's static header, as the same line in a fn does — in the declaration zone (D21a, the filed repro: 33, was 37)
# and after the first statement (D21b: 33, was 37); a `var P: *Str = gt;` in the zone takes the same address (the
# crossos z_* rows). The untyped `var H = gt;` keeps gt's first word at top level (D22a, the filed repro: 0, pinned;
# D22b `H == load64(&gt)`).
#
# 6.7.15 (the user's decision D17, 2026-10-18; issues/2026-10-17-toplevel-str-handle-from-inline-str-global-declared-
# below-refused-as-copy-init.md): a zone `var H: Str = gt;` with gt declared BELOW H binds too (D21c, the filed repro
# verbatim: 33 on every leg — refused "cannot copy-init 'H' from a global declared below it" through 6.7.14): gt's
# address is static, so the bind needs no layout pass 1 could not see.
#
# 6.7.15 (the user's decision D16, 2026-10-18; issues/2026-10-17-inline-str-assigned-into-str-pointer-keeps-data-
# word.md): an inline `Str` ASSIGNED into a `*Str` — `p = t`, `p = gt` (a `*Str` local or parameter), `GP = gt` (a
# `*Str` global), a for step — takes the header's address, as the declaration `var p: *Str = t;` does since 6.7.14
# (D16a, the filed repro verbatim: 7, was 0 — the data word); `GP = gt` is not warned "assigning non-pointer to typed
# pointer" (D16b; it was); a frame's `GP = t` is refused by name with the words `G = t` into a `Str` global has (X14).
#
# 6.7.15 (issues/archived/2026-10-17-str-pointer-dereference-into-str-parameter-passes-data-word.md): a `*Str` dereference into
# a `Str` parameter — `str_len(*p)`, `f(**pp)`, `str_len(*w.p)`, `h.eq(*p)` — passes the header p points at (its
# address, p), as `str_len(p)` does; it passed the header's first word, the data pointer, as the header (SD1, the filed
# repro verbatim: 5555, was 5500).
# 6.7.16 (issues/archived/2026-10-18-generic-str-instance-dereference-argument-passes-data-word.md): ... and into a generic's `x: T`
# at T = Str, which is address-passed (its struct-mask bit set, so the by-value arm never ran) — `gg<Str>(*p)`, the
# inferred `gg(*p)` (6.7.15's D12 (a) binds T = Str), wrapped, `*w.p`, `**pp`, `*gsp()`, a second argument, a tail
# call, a capture, a forwarder, a generic method, top level (the tcyr's sd_g* rows, R_TOP15): the header's data word
# went in as the header (SD2, the filed repro verbatim: 43, was 244).
#
# 6.7.15 (the user's decision D14, 2026-10-18; issues/2026-10-17-inline-str-assigned-from-str-pointer-or-if-expression-
# stores-one-word.md): `t = p` and `t = *p` with t an inline `Str` and p a `*Str` copy the header p points at, as `t = a`
# from a handle does (D20 (a)) and `var t: Str = *p;` does (D14a, the filed repro verbatim: 55, was 22 — t.data = p,
# t.len stale); `t = *p` is not warned "assigning non-pointer to typed pointer" (D14b; it was). An if-expression of
# `Str` handles keeps the one-word store, documented (the user's decision D15, 2026-10-18: its value is untyped, as for
# every inline struct — D15, pinned: 22 with today's warning).
#
# 6.7.16 (issues/archived/2026-10-18-inline-str-from-double-str-pointer-single-deref-stores-one-word.md): `t = *pp` with pp a
# `**Str` (so `*pp` is the `*Str` 6.7.13's D9 (a) made it) copies the header that `*Str` points at, as `t = p` does
# (D14, above): it stored the header's address into t.data and left t.len stale (PP1, the filed repro verbatim: 55, was
# 22; no warning before or after). Into a `*Str` or a handle `q = *pp` stays the rebind `q = p` is (the tcyr's pps_*
# controls).
#
# 6.7.16 (the user's decision D20, 2026-10-19; issues/2026-10-18-str-handle-assigned-str-pointer-dereference-stores-
# data-word.md): `h = *p` into a `Str` HANDLE (p a `*Str`) rebinds h to the header p points at, as `h = p` does — a
# local, a parameter, a global, wrapped, a for step, at top level (the tcyr's hd_* rows, R_TOP12). It stored the
# header's data word as the handle with a false "assigning non-pointer to typed pointer" (HD1, the filed repro
# verbatim: 5 and no warning, was 0 and the warning).
#
# 6.7.16 (the user's decision D19, 2026-10-19; issues/2026-10-18-inline-str-into-str-pointer-field-or-double-pointer-
# keeps-data-word.md): an inline `Str` stored into a `*Str` FIELD — a local's, a global's, through a `*W`, nested, a
# `: *W` call's, a for step, at top level — or through a `**Str` (`*pp = gt`) takes its header's address, as `p = gt`
# into a `*Str` name does (6.7.15's D16): it stored the data word, silently (FD1 / FD2, the filed repros verbatim: 9
# and 7, were 0 and 0). A frame's t is refused by name into ANY field — a local struct's too (D19: `w.p = t` as `v.s =
# t`) — with the field's words, and through `*pp` with the pointer's (X15-X19).
#
# 6.7.16 (issues/archived/2026-10-19-str-field-assigned-str-pointer-dereference-stores-data-word.md): `*p` (p a `*Str`) into a
# `Str` FIELD — `w.s = *p`, `GW.s = *p`, through a `*W`, nested, a `: *W` call's, a for step, at top level, `**pp` — a
# literal's `Str` field (`W { *p, 1 }`, in a fn, in the zone and after a statement) and `return *p;` from a fn returning
# `Str` is p, as `v.s = p` and D20's `h = *p` are (the tcyr's hf_* rows, R_TOP16): each stored or returned the header's
# data word as the handle (HF1, the filed repro verbatim: `161010` exit 43, was `160111` exit 50).
#
# 6.7.16 (D19, issues/archived/2026-10-19-struct-literal-str-pointer-field-from-inline-str-stores-data-word.md): a struct
# LITERAL's `*Str` element from an inline `Str` — `W { gt, 1 }`, named, a nested struct's leaf, in a fn, in the zone and
# after a statement, a capture's t — takes its header's address, as `w.p = gt` does (the tcyr's pl_* rows, R_TOP17;
# PL1 / PL3 the filed repro and top-level line: 7, were 0); a frame's `W { t, 1 }` is refused with the field's words
# (PL2 verbatim, PL2b named, PL2c nested; it compiled, the data word stored). An untyped field keeps the word.
#
# 6.7.16 (the user's decision D74, 2026-10-20; issues/2026-10-19-str-declaration-from-double-str-pointer-single-deref-
# binds-handle.md): `var u: Str = *pp;` (pp a `**Str`) is u's own copy of the header, as `var u: Str = p;`, `= *p` and
# `= **pp` are — `(*pp)`, a `pp: **Str` parameter, a capture, `*GPPS`, `*gpps()`, `*w.pp`, `**ppp` (the tcyr's
# pps_decl_* rows); it bound u as a handle on the header (PD1, the filed repro verbatim: 55, was 15). At top level, in the
# declaration zone and after a statement, `var U: Str = *GPP;` and `var V: Str = GP;` copy too (D74 and D18 (a), whose
# zone-lane code kept `Str` out; R_TOP18 and the zone row) — both bound a handle. `var q: *Str = *pp;` and an untyped
# `var h = *pp;` stay the pointer.
#
# 6.7.16 (the user's decision D73, 2026-10-20; issues/2026-10-19-store-through-str-pointer-from-str-pointer-dereference-
# stores-data-word.md): `*p` (p a `*Str`) into a `*Str` SLOT is p, the header's address — `*q = *p` through a `*Str` or
# a `**Str` (`**qq = *p`, `*pp = *p`), `x = *p` / `GX = *p` into a `*Str` name, `var y: *Str = *p;` (in a fn, in the
# zone, after a statement), `w.p = *p` into a `*Str` field, a literal's `*Str` element, a `s: *Str` argument (`fps(*p)`,
# 6.7.15's arm took only a `Str` parameter) and `return *p;` from a fn returning `*Str` (the tcyr's ds_* rows, R_TOP19).
# Each took the header's data word (DS1, the filed repro verbatim: `20120121`, was `21020121`), the names and the
# declaration with a false "assigning non-pointer to typed pointer". `*q = *pp` (already the `*Str`) is unchanged.
#
# 6.7.16 (the user's decision D71, 2026-10-20; issues/archived/2026-10-19-dereference-of-address-of-inline-str-reads-data-word.md):
# `*(&t)` / `*&t` of an inline `Str` t is t itself, as 6.7.15's D21 A reads `*(&p)` as p — every D7 (1) arm reads it as
# the name: `var h: Str = *(&t);` (and the untyped `var h = *(&t);`) binds a handle on t, `f(*(&t))` / `fp(*(&t))` /
# `gg<Str>(*(&t))` / the inferred `gg(*&t)` / `h.eq(*(&t))` pass its header, `u = *(&t)` copies it into an inline u, `k
# = *(&t)` rebinds a handle, `p = *(&t)` / `var p: *Str = *&t;` take the address; a global's and a capture's too, in
# the zone and after a statement (the tcyr's amp_* rows, R_TOP20). It took t's data word (AMP1, the filed repro
# verbatim: `3 3 3` exit 3 and no warning, was `0 0 1` exit 0 with two false "assigning non-pointer to typed
# pointer"). A frame's t keeps every refusal t has, named at t (X20-X28). An untyped position keeps the word. The store
# side too: `*(&t) = v` of an inline `Str` local or global is `t = v` (a copy from `gt`, a handle, `*p`, a `: Str` call,
# a `Str` field, `*(&u)`; the tcyr's amp_st* rows, R_TOP21) — it wrote v's first word into t.data — and `*(&t) += 1` is
# refused as `t += 1` is (X29; it stepped t.data).
#
# 6.7.16 (met in the s16 lane's D73 / D71 bites): an inline `Str` returned from a fn returning `*Str` takes its header's
# address, as into every other `*Str` slot (6.7.14's D18 (c), 6.7.15's D16, D19) — `return gt;`, `((gt))`, `*(&gt)`, a
# method's (the tcyr's rp_* rows); it returned gt's data word — and a frame's `return t;` is refused by name, as from a
# fn returning `Str` (X30 / X31; it compiled).
#
# 6.7.17 (the user's decision D18, 2026-10-22; issues/2026-10-21-str-shapes-beyond-d19-d20-d71-d73.md row 1): a struct
# value of another type assigned into a `Str` HANDLE — a local, a parameter, a global, a `*Str` name; from a call, a
# method, an operator, an if-expression, `fncall0(&mkq)`, an inline struct name or global, a field, a dereference, wrapped,
# a for step, at top level — is refused by name with the words the same assignment into a `P` handle has (SH1-SH15; SH1
# the filed repro verbatim: it compiled and crashed — x86_64 139, cx 252, PE 5 — h holding Q1's word). A `*Q1`, a `Q2`
# handle and a `: *Q1` call keep the rebind, a `: Str` call its value (SHK1). And at every other `Str` slot (D18's class,
# met in the bite): a `Str` field (a local's, a global's, through a `*W`, a for step, top level), a literal's `Str`
# element (in a fn, in the zone), a store through a `*Str` / `**Str` and `return` from a fn returning `Str` (a tail call
# too) refuse it with the position's words, as a `P` there does (SP1-SP10; each stored or returned the struct's first
# word); a `: Str` value, a handle and a `*Q1` keep their store (SPK1).
#
# 6.7.17 (the user's decision D19, 2026-10-22; the same issue's row 2): `*p` of a `*Str` as a nested struct field's
# literal element reaching a `Str` first leaf — `O { *p, 1, 2 }` with O's first field a `WS { s: Str; n; }` — is p, as
# the direct literal `WS { *p, 1 }` stores it (6.7.16's SS-8): it stored the header's data word (NS1, the filed repro
# verbatim: 10, was 50; the tcyr's ns_* rows and R_TOP22: two levels deep, wrapped, a call's, top level). A `Str` value
# whose nested field opens with no `Str` leaf is refused by name, as a `Str` name there is (NS2).
#
# 6.7.17 (the user's decision D20, 2026-10-22; the same issue's row 3): `*(&t) = v` with t a closure's captured inline
# `Str` copies v's 16-byte header into the closure's copy of t, as `*(&t) = v` of a local t is `t = v` (6.7.16's D71)
# and a captured struct's `*(&s) = v` copies (6.7.13): it wrote v's first word into the copy's data word and left t.len
# (CA1, the filed repro verbatim: 2, was 7; the tcyr's ca_* rows: a captured handle, a `: Str` call, a local handle, a
# `Str` field, `*p`, an inline global, a method, another inline `Str`, a for step; the enclosing fn's t unchanged). An
# untyped value keeps the one-word store into t.data, as `t = x` does; another struct is refused (CA2).
#
# 6.7.17 (the user's decision D21, 2026-10-22; the same issue's row 4): a struct literal's NAMED `Str` field — `V { s: a,
# n: 1 }` — compiles, as the positional `V { a, 1 }` does: a `Str` field is one handle slot, not a nested struct. It was
# "named init not supported for nested struct fields — use positional" (NM1, the filed repro verbatim: 4). The element
# takes the positional field's checks: a frame's inline `Str` refused as would-dangle (NM2), another struct refused
# (NM3), `*p` of a `*Str` is p, a global's header its address (the tcyr's nm_* rows, in a fn, the zone, after a
# statement).
#
# 6.7.17 (the user's decision D22, 2026-10-22; the same issue's row 5): an untyped top-level declaration from a whole
# call returning `Str` — `var bb = str_from("xyz");`, a method (`h.clone()`), a generic's `Str` instance (`gg<Str>(h)`,
# the inferred `gg(h)`), wrapped — is a `Str` handle global, in the declaration zone and after the first statement, as
# the same line in a fn is: `bb.len` reads 3 (ZS1, the filed repro verbatim; ZS2 the zone line; the tcyr's zs_* rows),
# where it was "no struct type in scope for 'bb'". Its value is unchanged (the header's address). A name keeps its word
# (`var H = gt;`, D22a / D22b), and so do a field read and an if-expression (the tcyr's zs_word row).
#
# ROWS: R0 the filed repro verbatim; R1 tests/tcyr/crossos/inline_str_value.tcyr (its row count derived,
# floor 132) on x86_64 (plain, CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu — EMULATION, not
# hardware), cx (cxvm) and PE (wine, a private prefix); X1-X19 refused (the message first, ONE `^error`, no
# warning, no binary) on the x86_64, aarch64, cx and PE compilers; K1-K8 controls that compile and run on every
# leg (K9 the untyped positions of D18 (c)); U1-U2 a bare `var t: Str;` assigned a handle reads its own header on
# every leg; D20a the filed repro verbatim (5 — the pun read 5 too), D20b its `return t.len;` (5; the pun left it
# unwritten), D20c the filed row 3 (5) on every leg; D18a the D18 filed repro verbatim (1), D18b `var p: *Str = t;`
# (7), D18c `var p: *Str = gt;` (7, no warning); D21a / D21b the D21 filed repro in the zone and after a first
# statement (33), D21c a source declared below binds (33, D17), D22a / D22b the untyped top-level declaration's word
# (0; 1); D16a / D16b / X14 the assignment into a `*Str` (D16); SD1 a `*Str` dereference into a `Str` parameter;
# SD2 the same into a generic's `x: T` at T = Str (6.7.16);
# D14a / D14b the copy from a `*Str` (D14), D15 the if-expression's one-word store (pinned); PP1 the copy from `*pp` of a
# `**Str` (6.7.16); HD1 `h = *p` into a handle rebinds (6.7.16, D20); HF1 `w.s = *p` into a `Str` field is p (6.7.16); PL1 / PL3 a literal's `*Str` element takes an inline `Str`'s header, PL2 / PL2b / PL2c a frame's refused (6.7.16, D19); PD1 `var u: Str = *pp;` copies (6.7.16, D74); DS1 `*q = *p` stores p (6.7.16, D73); AMP1 `*(&t)` is t, X20-X28 a frame's refused through it, X29 `*(&t) += 1` refused (6.7.16, D71); X30 / X31 a frame's t returned from a fn returning `*Str` refused (6.7.16); FD1 / FD2 an inline `Str` into a `*Str` field
# / through a `**Str`, X15-X19 a frame's refused there (6.7.16, D19); SH1-SH15 a struct value of another type into a
# `Str` handle refused, SHK1 its rebind controls, SP1-SP10 / SPK1 the other `Str` slots (6.7.17, D18); NS1 the D19 filed
# repro verbatim (10 on every leg), NS2 a `Str` value off the chain refused (6.7.17, D19), NS3 / NS4 a nested element's
# `*(&t)` refused as t is (6.7.17, D71's rule); CA1 the D20 filed repro verbatim (2 on every leg), CA2 another struct
# refused there (6.7.17, D20), CA3 a captured t's `*(&t) += 1` refused (6.7.17); NM1 the D21 filed repro verbatim (4
# on every leg), NM2 / NM3 the named element keeps the `Str` field's refusals (6.7.17, D21); ZS1 the D22 filed repro
# verbatim (3 on every leg), ZS2 its zone line (6.7.17, D22); CMP a handle into the retyped methods builds
# byte-identical to the
# untyped methods on the x86_64, PE, aarch64 and cx compilers; AS1 an inline `Str` in an `async fn` across awaits
# (x86_64, CYRIUS_ASYNC=1).
#
# MUTATION LEDGER (2026-10-15; each mutant a scratch copy of the tree (src, lib, programs, this gate and its
# tcyr) with the one change, its cycc built from the mutated src, this gate run from the copy with CYCC= that
# cycc — so the aarch64 / cx / PE legs are built from the mutated src too):
#   n0 the tree before the fix (44ab2052)          -> RED 75: R0 x7 (exit 0), R1 x7 (SIGSEGV x5, a cx guest fault,
#                                                     a PE crash), X1-X13 x4 (each compiled), K1 x4, K2 x4, AS1 (139)
#   n1 `_istr_arg` returns at once                 -> RED 15: R0 x7, R1 x7 (f(t) 0, then a crash), AS1
#   n2 `_istr_decl` returns at once                -> RED 12: R1 x7 (var h: Str = t / var h = t / gt: 10 rows), K2
#                                                     x4, AS1
#   n3 `_istr_src` answers 0 (the copy-init copies) -> RED 7: R1 x7 (b_decl / b_untyped / b_wrap / g_bind: h a copy)
#   n4 `_istr_asg` returns at once                 -> RED 23: R1 x7 (h = t: 8 rows), X4 X5 X10 x4, K1 x4
#   n5 `_istr_ret` returns at once                 -> RED 31: R1 x7 (return gt), X1-X3 X12 X13 x4, K1 x4
#   n6 `_istr_fsc` answers 0                       -> RED 19: R1 x7 (w2.s = gt, p.s = gt), X6 X7 X11 x4
#   n7 `_istr_lit` returns at once                 -> RED 15: R1 x7 (W { gt, 1 }: a crash), X8 x4, K1 x4
#   n8 `_istr_dsto` returns at once                -> RED 15: R1 x7 (*ps = gt), X9 x4, K1 x4
#   n9 `_istr_ra` without `_fn_local_addr = 1`     -> RED 18: R0 x7 (`return f(t);` jumped out of t's frame: 8-248),
#                                                     R1 x7 (8-10 rows), K2 x4
#   n10 `_istr_name` without the capture rung      -> RED 7: R1 x7 (c_bindcap: `var h: Str = t` copied the capture)
#   (n0-n10 were measured with X3 — `var t: Str;` returned, refused — which the review fix moved out: the bare
#   declaration's D7 question is open, issues/archived/2026-10-15-str-handle-into-inline-str-stores-one-word.md)
#   2026-10-16 (the review fix; the same scratch-copy method):
#   n11 `_istr_bare` / `_istr_bare_cap` answer 0   -> RED 15: R1 x7 (the five u_* rows), U1 x4, U2 x4 (t's unwritten
#                                                     length: 224 / 24 / 0 / 0 and 1 / 0 / 0 / 1)
#   n12 `_istr_cpmark` returns at once             -> RED 7: R1 x7 (u_copy 22, u_cap 22: the copy read its length)
#   (n11 / n12 retired with the marks by 6.7.14's D20 (a): the bare declaration is D7 (1)'s.)
#   2026-10-17 (6.7.14, D20 (a); the same scratch-copy method):
#   d1 the lane before D20 (c778c9817)             -> RED 22: R1 x7 (17 rows: b_bare, u_copy, the h_* copies — 22 the
#                                                     pun, t.len stale), X3 x4 (compiled), D20b x7 (0), D20c x4
#                                                     (224 / 24 / 0 / 0)
#   d2 `_istr_hop` answers 0 (no handle name)      -> RED 21: R1 x7 (8 rows: a local, parameter, global, `(a)`, a for
#                                                     step, an inline global, top level), D20a x7 (0), D20b x7 (0)
#   d3 `_istr_call` answers 0 (no `: Str` call)    -> RED 7: R1 x7 (h_gen 22: a generic call; a plain call is typed
#                                                     by `_istr_hcp` too)
#   d4 `_istr_hcp` answers 0 (no method / field)   -> RED 7: R1 x7 (h_meth, h_field, h_fieldp)
#   2026-10-17 (6.7.14, D18 (c)):
#   e1 the lane before D18 (0807784c2: untyped      -> RED 26: R1 x7 (h.eq(t) 0, then h.cat(t) read "abcdefg" as a
#      methods, no `*Str` declaration arm)              header: SIGSEGV x5, cx 12 rows, a PE crash), D18a x7 (0),
#                                                     D18b x4 (0), D18c x8 (warned; 0)
#   e2 `_istr_pdecl` answers 0                      -> RED 19: R1 x7 (q_ptr 73, q_pglob 33, q_pbare 5, the top-level
#                                                     `*Str`, and two encoder rows the wild `p.len = 3` corrupted),
#                                                     D18b x4, D18c x8
#   e3 `_istr_pdecl` without its SPSC              -> RED 4: D18c x4 (warned "assigning non-pointer to typed pointer")
#   e4 lib/str.cyr's five methods untyped again     -> RED 14: R1 x7, D18a x7 (0)
#   2026-10-17 (6.7.14, D21 (a)):
#   f1 the lane before D21 (11dc74b46)             -> RED 21: R1 x7 (HL, HZ: a copy, 7; HZ2 / PZ: the word), D21a x7
#                                                     (37), D21b x7 (37)
#   f2 `_istr_gz` answers 0 (the zone replay)      -> RED 14: R1 x7 and D21a x7 refused "declared below" (pass 1 made
#                                                     H a handle, the replay's copy path refuses it)
#   f3 `_istr_gsrc` answers 0 (pass 1 inline)      -> RED 14: R1 x7 (z_bind, z_wrap), D21a x7 (37: copied)
#   f4 `_istr_src` after the top-level arm again   -> RED 14: R1 x7 (R_TOP5: a copy), D21b x7 (37)
#   f5 the replay without its declared-below guard -> RED 4: D21c x4 (built) — retired by 6.7.15's D17 (below)
#   2026-10-17 (6.7.14, D22 (b), the pins):
#   g1 `_uci_ps` answers at top level (D22's (a))  -> RED 7: R1 x7 (R_TOP6: `var UL = gz;` after a statement became
#                                                     gz's handle); the zone's D22a / D22b pin the replay's untyped
#                                                     path, which offers no handle to mutate to
#   2026-10-18 (6.7.15, D17; the same scratch-copy method):
#   h1 the declared-below guard restored in        -> RED 14: R1 x7 (the zone line HB refused), D21c x7
#      `_istr_gz` (the lane before D17)               (refused "cannot copy-init 'H' ...")
#   2026-10-18 (6.7.15, D16):
#   i1 `_istr_dst` without its `*Str` answers 3 / 4 -> RED 26: R1 x7 (9 rows: the pa_* rows, R_TOP7 — the data
#      (the lane before D16)                          word), X14 x4 (built), D16a x7 (0), D16b x4 (warned) + x4 (0)
#   i2 `_istr_asg` without its SPSC                -> RED 4: D16b x4 (warned "assigning non-pointer to typed pointer")
#   2026-10-18 (6.7.15, the `*Str` dereference argument):
#   j1 `_sarg_istr_dx` never called (the lane     -> RED 14: R1 x7 (str_len(*p) read the string as a header: SIGSEGV x5,
#      before)                                        a cx guest fault, PE 5), SD1 x7 (5500)
#   2026-10-18 (6.7.15, D14):
#   k1 `_istr_hop` without the `*Str` names        -> RED 14: R1 x7 (6 rows, `t = p`: 22), D14a x7 (22)
#   k2 `_asg_dstar` without `_istr_dxa`            -> RED 18: R1 x7 (11 rows, `t = *p`: 22 + the warning), D14b x4
#                                                     (warned) + x7 (22)
#   2026-10-19 (6.7.16, `t = *pp` of a `**Str`; the same scratch-copy method):
#   l1 `_asg_dstar` asking `_hl_dstar_x(.., 1)`    -> RED 14: R1 x7 (10 rows: the pps_* copies and R_TOP11 — t.data the
#      (the fix reverted)                             header's address, t.len stale), PP1 x7 (22)
#   2026-10-19 (6.7.16, D20 `h = *p` into a handle; the same scratch-copy method):
#   m1 `_istr_dxa` returning 0 for a handle        -> RED 18: R1 x7 (10 rows: the hd_* rows and R_TOP12 — the data
#      (the fix reverted)                             word as the handle), HD1 x4 (warned) + x7 (0)
#   2026-10-19 (6.7.16, D19 an inline `Str` into a `*Str` field / through a `**Str`; the same scratch-copy method):
#   o1 the lane before D19 (the fix reverted)      -> RED 41: R1 x7 (16 rows: 14 pa_fld_* / pa_pp_* / R_TOP13 /
#                                                     R_TOP14 — the data word — and two encoder rows the wild
#                                                     `w.p.len = 3` corrupted), X15-X19 x4 (each compiled), FD1 x7
#                                                     (0), FD2 x7 (0)
#   o2 `_istr_pfld` returns at once (no field)     -> RED 30: R1 x7 (10 rows: the field rows, R_TOP13 and the two
#                                                     encoder rows), X15-X17 X19 x4, FD1 x7 (0)
#   o3 `_istr_dspp` answers 0 (no `*pp`)           -> RED 18: R1 x7 (6 rows: the `*pp` rows, R_TOP14), X18 x4, FD2
#                                                     x7 (0)
#   2026-10-20 (6.7.16, a `*Str` dereference into a generic's `x: T` at T = Str; the same scratch-copy method):
#   q1 `_try_push_struct_addr_arg` without its     -> RED 14: R1 x7 (11 rows: the sd_g* rows but the controls, and
#      `_sarg_istr_dx` arm (the fix reverted)         R_TOP15 — the data word as the header), SD2 x7 (244)
#   2026-10-20 (6.7.16, `*p` into a `Str` field / a literal's / a `: Str` return; the same scratch-copy method):
#   r1 `_istr_vdx` answers 0 (the fix reverted)    -> RED 14: R1 x7 (16 rows: the hf_* rows, R_TOP16 — the data word as
#                                                     the handle), HF1 x7 ('160111', exit 50)
#   2026-10-20 (6.7.16, D19 a struct literal's `*Str` element; the same scratch-copy method):
#   s1 EMIT_STRUCT_FIELD_W without `_istr_pfld`   -> RED 33: R1 x7 (8 rows: the pl_* rows, R_TOP17 — the data word —
#      (the fix reverted)                             and the two encoder rows), PL1 x7 (0), PL2 / PL2b / PL2c x4 (each
#                                                     compiled), PL3 x7 (0)
#   2026-10-20 (6.7.16, D74 `var u: Str = *pp;` and the top-level twins; the same scratch-copy method):
#   t1 `_hl_dpp_str` answering mode 2 only, and    -> RED 14: R1 x7 (7 rows: the pps_decl_* copies, the zone row and
#      `_gz_pnat` without `Str` (the fix reverted)    R_TOP18 — handles), PD1 x7 (15)
#   2026-10-20 (6.7.16, D73 `*p` into a `*Str` slot; the same scratch-copy method):
#   u1 every D73 arm reverted (`_istr_dsdx`,       -> RED 14: R1 x7 (17 rows: the ds_* rows, R_TOP19 — the data word),
#      `_istr_pfdx`, `_istr_pvd`, `_istr_gzdx`,       DS1 x7 ('21020121')
#      `_istr_ldx`'s `*Str`, `_istr_rstr`'s `*Str`,
#      `_istr_dxh`'s 3 / 4, `_pptr_param` back)
#   2026-10-20 (6.7.16, D71 `*(&t)` of an inline `Str` is t; the same scratch-copy method):
#   v1 `_istr_amp` answers 0 (the reading         -> RED 54: R1 x7 (a crash — SIGSEGV, a cx guest fault, PE — the
#      reverted)                                      amp_* rows read t's data word as a header), X20-X28 x4 (each
#                                                     compiled), AMP1 x4 (warned) + x7 ('0 0 1', exit 0)
#   v2 `_istr_amp_dst` answers 0 (the store side)  -> RED 11: R1 x7 (4 rows: amp_st*, R_TOP21 — the first word stored),
#                                                     X29 x4 (compiled)
#   2026-10-20 (6.7.16, an inline `Str` returned from a fn returning `*Str`; the same scratch-copy method):
#   w1 `_istr_ret` asking `Str` only (the fix       -> RED 15: R1 x7 (4 rows: rp_ret, rp_len — the data word — and the
#      reverted)                                      two encoder rows the wild `p.len = 3` corrupted), X30 / X31
#                                                     x4 (each compiled)
#   2026-10-22 (6.7.17, D18 a struct value into a `Str` handle; the same scratch-copy method):
#   x1 `_istr_hdt` answers `dt` (the fix reverted) -> RED 60: SH1-SH15 x4 (each compiled)
#   x2 `_istr_vsid` only parses, `_istr_tcd` 0     -> RED 40: SP1-SP10 x4 (each compiled)
#   2026-10-22 (6.7.17, D19 `*p` into a nested `Str` leaf; the same scratch-copy method):
#   y1 `_spi_dsrc` without its `Str` arm           -> RED 18: R1 x7 (the ns_* rows and R_TOP22 — the data word),
#      (the fix reverted)                             NS1 x7 (50), NS2 x4 (compiled)
#   y2 `_spi_dsrc` without its `*(&t)` test        -> RED 8: NS3 x4, NS4 x4 (each compiled, the data word carried)
#   2026-10-22 (6.7.17, D20 a captured t's `*(&t) = v`; the same scratch-copy method):
#   z1 `_istr_amp_dst` returning 0 for a capture     -> RED 18: R1 x7 (the ca_* rows — the first word into t.data, t.len
#      (the fix reverted)                             7), CA1 x7 (7), CA2 x4 (compiled)
#   z2 `_istr_inl_dst` without the override          -> RED 7: R1 x7 (ca_call / ca_field / ca_dx / ca_meth / ca_step:
#                                                     one word)
#   z3 `_istr_amp_dst` returning 0 for a capture's  -> RED 4: CA3 x4 (compiled)
#      compound operator (the fix reverted)
#   2026-10-22 (6.7.17, D21 a named `Str` field; the same scratch-copy method):
#   n1 `_sl_named_nest` answering 1 for `Str`      -> RED 22: R1 x7 (the file stops compiling: the nm_* rows),
#      (the fix reverted)                             NM1 x7 (refused), NM2 x4 / NM3 x4 (the named-init refusal first)
#   2026-10-22 (6.7.17, D22 a top-level untyped `: Str` call; the same scratch-copy method):
#   s1 `_gu_okz` / `_gu_lstr` answering no `Str`   -> RED 18: R1 x7 (the file stops compiling: the zs_* rows),
#      (the fix reverted)                             ZS1 x7, ZS2 x4 (refused "no struct type in scope")
#   s2 `_var_rhs_mchain` without its unwrap (the    -> RED 7: R1 x7 (the file stops compiling: zs_wrapm's `(h.clone())`
#      compiler before the fix)                       and the top-level `(zsl.clone())` untyped)
#   real tree                                       -> GREEN
#
# Exit 1 = a row failed (or the compiler is missing); every leg that cannot run says so by name (a SKIP).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
G=inline_str_value
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
WP="$T/wine"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT"
fails=0
skips=0
rows=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

A64="$T/cc_a64"
QEMU=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$A64" 2> "$T/cc_a64.err" && [ -s "$A64" ]; then chmod +x "$A64"; QEMU=1
    else bad "src/main_aarch64.cyr did not build: $(grep '^error' "$T/cc_a64.err" | head -1 || true)"; fi
else echo "  SKIP the aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
CX=0
CXC="$T/cc_cx"
if "$CC" < src/main_cx.cyr > "$CXC" 2> "$T/cc_cx.err" && [ -s "$CXC" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
    chmod +x "$CXC" "$T/cxvm"; CX=1
else bad "src/main_cx.cyr or programs/cxvm.cyr did not build: $(grep '^error' "$T/cc_cx.err" "$T/cxvm.err" | head -1 || true)"; fi
WINE=0
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP the PE run leg — wine not installed (the PE refusals still run)"; skips=$((skips + 1)); fi

# compile <leg> <name>: $T/<name>.<leg> (+ .err); rc in $crc. x86_64:VAR=1 is the host compiler under VAR.
compile() {
    crc=0
    case $1 in
        x86_64)   timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        x86_64:*) env "${1#x86_64:}" timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        aarch64)  timeout 60 "$A64" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        cx)       timeout 60 "$CXC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        pe)       CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
    esac
}
legs() {
    l="x86_64"
    [ "$QEMU" -eq 1 ] && l="$l aarch64"
    [ "$CX" -eq 1 ] && l="$l cx"
    echo "$l pe"
}
# execute <leg> <name>: runs $T/<name>.<leg>; exit in $got, the last output line in $last
execute() {
    got=0
    chmod +x "$T/$2.$1"
    case $1 in
        x86_64*) timeout 60 "$T/$2.$1" > "$T/$2.$1.out" 2>&1 || got=$? ;;
        aarch64) timeout 120 qemu-aarch64 "$T/$2.$1" > "$T/$2.$1.out" 2>&1 || got=$? ;;
        cx)      timeout 120 "$T/cxvm" < "$T/$2.$1" > "$T/$2.$1.out" 2>&1 || got=$? ;;
        pe)      cp "$T/$2.$1" "$T/$2.exe"
                 (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                     WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$2.exe" > "$T/$2.$1.out" 2> /dev/null) || got=$? ;;
    esac
    last=$(tail -1 "$T/$2.$1.out" | tr -d '\r')
}
# refused <name> <fragment> <what>: the source is $T/<name>.cyr; ONE `^error` line, holding <fragment>
refused() {
    rows=$((rows + 1))
    for leg in $(legs); do
        compile "$leg" "$1"
        n=$(grep -c '^error' "$T/$1.$leg.err" || true)
        w=$(grep -c '^warning' "$T/$1.$leg.err" || true)
        if [ "$crc" -eq 0 ]; then bad "$1 $3 ($leg): BUILT (rc 0)"
        elif ! grep '^error' "$T/$1.$leg.err" | head -1 | grep -qF "$2"; then bad "$1 $3 ($leg): refused, but not as expected: $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"
        elif [ "$n" -ne 1 ]; then bad "$1 $3 ($leg): $n error lines (want 1)"
        elif [ "$w" -ne 0 ]; then bad "$1 $3 ($leg): a warning beside the refusal: $(grep '^warning' "$T/$1.$leg.err" | head -1 || true)"
        elif [ -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): refused, but a binary was written"
        else ok "$1 $3 ($leg): refused"; fi
    done
}
# runs <name> <want> <what> [<legs>]: compiles clean and exits <want> on every leg
runs() {
    rows=$((rows + 1))
    for leg in ${4:-$(legs)}; do
        [ "$leg" = pe ] && [ "$WINE" -eq 0 ] && continue
        compile "$leg" "$1"
        if [ "$crc" -ne 0 ] || [ ! -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): did not build (rc $crc): $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"; continue; fi
        execute "$leg" "$1"
        if [ "$got" = "$2" ]; then ok "$1 $3 ($leg): exit $got"; else bad "$1 $3 ($leg): exit $got, want $2"; fi
    done
}
XLEGS="x86_64 x86_64:CYRIUS_IR=1 x86_64:CYRIUS_IR=3 x86_64:CYRIUS_DCE=1"
OLEGS=""
[ "$QEMU" -eq 1 ] && OLEGS="$OLEGS aarch64"
[ "$CX" -eq 1 ] && OLEGS="$OLEGS cx"
[ "$WINE" -eq 1 ] && OLEGS="$OLEGS pe"

# --- R0: the filed repro, verbatim (exit 7; 0 = the data word read as the header) ---
cat > "$T/R0.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
fn main() { var t: Str = Str { "abcdefg", 7 }; return f(t); }
var r = main();
syscall(SYS_EXIT, r);
EOF
runs R0 7 "the filed repro: f(t) into \`s: Str\`" "$XLEGS $OLEGS"

# --- R1: the crossos values file on every leg ---
TC=tests/tcyr/crossos/inline_str_value.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC")
FLOOR=239   # 6.7.16: + the pps_* rows, R_TOP11; + the hd_* rows, R_TOP12 (D20); + the pa_fld_* / pa_pp_* rows, R_TOP13 / R_TOP14 (D19); + the sd_g* rows, R_TOP15; + the hf_* rows, R_TOP16; + the pl_* rows, R_TOP17; + the pps_decl_* rows, R_TOP18; + the ds_* rows, R_TOP19; + the amp_* rows, R_TOP20 / R_TOP21; + the rp_* rows
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi
cp "$TC" "$T/R1.cyr"
rows=$((rows + 1))
for leg in $XLEGS $OLEGS; do
    compile "$leg" R1
    if [ "$crc" -ne 0 ] || [ ! -s "$T/R1.$leg" ]; then bad "R1 $TC ($leg): did not build: $(grep '^error' "$T/R1.$leg.err" | head -1 || true)"; continue; fi
    execute "$leg" R1
    if [ "$got" -eq 0 ] && [ "$last" = "$N passed, 0 failed ($N total)" ]; then ok "R1 ($leg): $last"
    else bad "R1 ($leg): exit $got, '$last' (want $N passed): $(grep FAIL "$T/R1.$leg.out" | head -2 | tr '\n' ' ')"; fi
done

H='include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str): i64 { return str_len(s); }
struct W { s: Str; n; }
fn new_w(): *W { return alloc(sizeof(W)); }
fn new_slot(): *Str { return alloc(8); }
var gt: Str = Str { "abcdefg", 7 };
var G: Str = 0;
var U = 0;'
row() { printf '%s\n%s\nalloc_init();\nsyscall(60, go());\n' "$H" "$2" > "$T/$1.cyr"; }
MR="cannot return the inline Str 't' from a fn returning Str - its header lives in this frame and would dangle (return a handle: str_new(data, len))"
MG="cannot store the inline Str 't' into a global - its header lives in this frame and would dangle (store a handle: str_new(data, len))"
MF="cannot store the inline Str 't' into a field - its header lives in this frame and would dangle (store a handle: str_new(data, len))"
MP="cannot store the inline Str 't' through a pointer - its header lives in this frame and would dangle (store a handle: str_new(data, len))"

# --- X: a frame's inline Str where it would outlive the frame ---
row X1 'fn mk(): Str { var t: Str = Str { "abcdefg", 7 }; return t; }
fn go(): i64 { var h = mk(); return f(h); }'
refused X1 "$MR" "the filed table's \`return t;\` from \`fn mk(): Str\` (was 0)"
row X2 'fn mk(): Str { var t: Str = Str { "abcdefg", 7 }; return ((t)); }
fn go(): i64 { return f(mk()); }'
refused X2 "$MR" "\`return ((t));\`"
row X3 'fn mk(): Str { var t: Str; t.data = "abc"; t.len = 3; return t; }
fn go(): i64 { return f(mk()); }'
refused X3 "$MR" "\`var t: Str;\` (inline, no literal) returned (D20 (a); 6.7.13 compiled it, the first word)"
row X4 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; G = t; return f(G); }'
refused X4 "$MG" "\`G = t;\` into a Str global"
row X5 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; G = (t); return 0; }'
refused X5 "$MG" "\`G = (t);\`"
row X6 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: W = W { 0, 1 }; w.s = t; return f(w.s); }'
refused X6 "$MF" "\`w.s = t;\` into a Str field of a local"
row X7 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var p: *W = new_w(); p.s = (t); return 0; }'
refused X7 "$MF" "\`p.s = (t);\` through a \`*W\`"
row X8 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: W = W { t, 1 }; return f(w.s); }'
refused X8 "$MF" "\`W { t, 1 }\`, a literal's Str field"
row X9 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var ps: *Str = new_slot(); *ps = t; return 0; }'
refused X9 "$MP" "\`*ps = t;\` through a \`*Str\`"
row X10 'fn go(): i64 { var c = || { var t: Str = Str { "abcdefg", 7 }; G = t; return 0; }; return callptr(c); }'
refused X10 "$MG" "a closure body's own inline Str into a global"
row X11 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: W = W { 0, 1 }; var i = 0; for (i = 0; i < 1; w.s = t) { i = i + 1; } return 0; }'
refused X11 "$MF" "a for step's field store"
row X12 'fn W_name(self: *W): Str { var t: Str = Str { "abc", 3 }; return t; }
fn go(): i64 { var w: W = W { 0, 1 }; return f(w.name()); }'
refused X12 "$MR" "a method returning Str"
row X13 'fn mk(c): Str { if (c == 1) { var t: Str = Str { "abc", 3 }; return t; } return 0; }
fn go(): i64 { return f(mk(1)); }'
refused X13 "$MR" "\`return t;\` inside a block"
row X14 'var GP: *Str = 0;
fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; GP = t; return str_len(GP); }'
refused X14 "$MG" "\`GP = t;\` into a \`*Str\` global (D16: the header's address would dangle; the data word through 6.7.14)"
# X15-X19 (D19): a frame's t into a `*Str` FIELD — a local struct's too — is refused as `w.s = t` into a `Str` field is
# (X6), and through a `**Str` as `*ps = t` through a `*Str` is (X9); through 6.7.15 each compiled, the data word stored.
row X15 'struct WP { p: *Str; n; }
fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: WP = WP { 0, 1 }; w.p = t; return str_len(w.p); }'
refused X15 "$MF" "\`w.p = t;\` into a \`*Str\` field of a local (D19, the decided shape)"
row X16 'struct WP { p: *Str; n; }
var GW: WP = WP { 0, 0 };
fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; GW.p = t; return 0; }'
refused X16 "$MF" "\`GW.p = t;\` into a \`*Str\` field of a global"
row X17 'struct WP { p: *Str; n; }
fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: WP = WP { 0, 1 }; var pw: *WP = &w; pw.p = (t); return 0; }'
refused X17 "$MF" "\`pw.p = (t);\` through a \`*WP\`"
row X18 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var q: *Str = 0; var pp: **Str = &q; *pp = t; return 0; }'
refused X18 "$MP" "\`*pp = t;\` through a \`**Str\`"
row X19 'struct WP { p: *Str; n; }
fn go(): i64 { var t: Str; var w: WP = WP { 0, 1 }; var i = 0; for (i = 0; i < 1; w.p = t) { i = i + 1; } return 0; }'
refused X19 "$MF" "a for step's \`*Str\` field store of a bare \`var t: Str;\`"
# X20-X28 (6.7.16, D71): `*(&t)` / `*&t` of a frame's t is t, so it keeps every refusal t has, named at t; through
# 6.7.15 each compiled, t's data word stored or returned.
row X20 'fn mk(): Str { var t: Str = Str { "abcdefg", 7 }; return *(&t); }
fn go(): i64 { return f(mk()); }'
refused X20 "$MR" "\`return *(&t);\` from a fn returning Str (D71)"
row X21 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; G = *(&t); return 0; }'
refused X21 "$MG" "\`G = *(&t);\` into a Str global"
row X22 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: W = W { 0, 1 }; w.s = *(&t); return 0; }'
refused X22 "$MF" "\`w.s = *(&t);\` into a Str field"
row X23 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var ps: *Str = new_slot(); *ps = *(&t); return 0; }'
refused X23 "$MP" "\`*ps = *(&t);\` through a \`*Str\`"
row X24 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var q: *Str = 0; var pp: **Str = &q; *pp = *((&t)); return 0; }'
refused X24 "$MP" "\`*pp = *((&t));\` through a \`**Str\`"
row X25 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: W = W { *&t, 1 }; return 0; }'
refused X25 "$MF" "\`W { *&t, 1 }\`, a literal's Str field"
row X26 'var GP: *Str = 0;
fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; GP = *(&t); return 0; }'
refused X26 "$MG" "\`GP = *(&t);\` into a \`*Str\` global"
row X27 'struct WP { p: *Str; n; }
fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: WP = WP { 0, 1 }; w.p = *(&t); return 0; }'
refused X27 "$MF" "\`w.p = *(&t);\` into a \`*Str\` field"
row X28 'fn go(): i64 { var t: Str; var w: W = W { 0, 1 }; var i = 0; for (i = 0; i < 1; w.s = *(&t)) { i = i + 1; } return 0; }'
refused X28 "$MF" "a for step's \`w.s = *(&t)\` of a bare \`var t: Str;\`"
row X29 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; *(&t) += 1; return t.len; }'
refused X29 "compound assignment to struct 't' is refused - a struct value is not an integer or a float (write \`a = a + b\`)" "\`*(&t) += 1;\` refused as \`t += 1;\` is (it stepped t.data)"
# X30 / X31 (6.7.16): a frame's t returned from a fn returning `*Str` — refused as from a fn returning `Str` (it compiled,
# the data word returned; a global's `return gt;` returns gt's address, the tcyr's rp_* rows).
MRP="cannot return the inline Str 't' from a fn returning *Str - its header lives in this frame and would dangle (return a handle: str_new(data, len))"
row X30 'fn mk(): *Str { var t: Str = Str { "abcdefg", 7 }; return t; }
fn go(): i64 { return str_len(mk()); }'
refused X30 "$MRP" "\`return t;\` from a fn returning \`*Str\`"
row X31 'fn mk(): *Str { var t: Str; t.data = "ab"; t.len = 2; return *((&t)); }
fn go(): i64 { return str_len(mk()); }'
refused X31 "$MRP" "\`return *((&t));\` of a bare \`var t: Str;\` from a fn returning \`*Str\`"

# --- K: controls (a global's or a capture's header does not dangle; untyped positions keep the word) ---
row K1 'fn mk(): Str { return gt; }
fn go(): i64 { var w: W = W { gt, 1 }; G = gt; var ps: *Str = new_slot(); *ps = gt; return f(mk()) + f(w.s) + f(G) + f(load64(ps)); }'
runs K1 28 "a global inline Str: returned, into a literal's field, a Str global, through a \`*Str\`"
row K2 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var h: Str = t; return f(h); }'
runs K2 7 "a frame's inline Str bound to a handle, then a tail call (it diverts)"
row K3 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var c = || { G = t; return 0; }; callptr(c); return f(G); }'
runs K3 7 "a captured inline Str (the environment's copy) into a global"
row K4 'fn mkc() { var t: Str = Str { "abcdefg", 7 }; return || { return f(t); }; }
fn go(): i64 { var c = mkc(); var x: i64[8]; var i = 0; while (i < 8) { x[i] = 0 - 1; i = i + 1; } return callptr(c) + x[1] + 1; }'
runs K4 7 "a closure returned out of t's frame keeps its copy"
row K5 'fn mk() { var t: Str = Str { "abcdefg", 7 }; return t; }
fn go(): i64 { var w = mk(); if (w == 0) { return 1; } return 2; }'
runs K5 2 "an untyped fn's \`return t;\` keeps the word (no Str value is taken)"
row K6 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; U = t; if (U == load64(&t)) { return 3; } return 4; }'
runs K6 3 "an untyped global keeps the word"
row K7 'fn mk(): Str { var h = str_from("abcde"); return h; }
fn go(): i64 { return f(mk()); }'
runs K7 5 "a Str handle returned from a fn returning Str"
row K8 'fn go(): i64 { var a = str_from("abcde"); var x = 0; x = a; var t: Str = Str { "zz", 2 }; t = x; return t.len * 10 + f(t); }'
runs K8 22 "an untyped source into an inline Str keeps the one-word store (t.len stays 2)"

row K9 'fn id(x): i64 { return x; }
fn go(): i64 {
    var t: Str = Str { "abcdefg", 7 };
    var w = load64(&t);
    var h = str_from("zz");
    var v = vec_new();
    vec_push(v, t);
    var x = (t, 1);
    var c = 1;
    var b = if (c == 1) { t } else { h };
    var n = 0;
    if (fncall1(&id, t) == w) { n = n + 1; }
    if (callptr(&id, t) == w) { n = n + 1; }
    if (vec_get(v, 0) == w) { n = n + 1; }
    if (x.0 == w) { n = n + 1; }
    if (b == w) { n = n + 1; }
    return n;
}'
runs K9 5 "untyped positions keep t's data word: fncall1, callptr, a vec, a tuple element, an if-expression branch (D18 (c))"

# --- D23: a handle BOUND to a frame's inline Str escapes as `&t` does — it compiles, no diagnostic (D23 (b), documented) ---
cat > "$T/D23a.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
fn smash(): i64 { var a: i64[32]; var i = 0; while (i < 32) { a[i] = 0; i = i + 1; } return a[3]; }
fn mk(): Str { var t: Str = Str { "abcdefg", 7 }; var h: Str = t; return h; }
fn main() { var h = mk(); smash(); return f(h); }
var r = main();
syscall(SYS_EXIT, r);
EOF
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" D23a
    if [ "$crc" -ne 0 ] || [ ! -s "$T/D23a.$leg" ]; then bad "D23a ($leg): the bound handle's \`return h;\` did not build (rc $crc): $(grep '^error' "$T/D23a.$leg.err" | head -1 || true)"
    elif grep -qE '^(error|warning)' "$T/D23a.$leg.err"; then bad "D23a ($leg): a diagnostic: $(grep -E '^(error|warning)' "$T/D23a.$leg.err" | head -1)"
    else ok "D23a the filed repro: \`var h: Str = t; return h;\` compiles clean ($leg) — it dangles as \`&t\` does"; fi
done

# --- U: a bare `var t: Str;` assigned a Str handle reads its OWN header, the handle's copied (D20 (a)) ---
row U1 'fn go(): i64 { var t: Str; t = str_from("hello"); return str_len(t); }'
runs U1 5 "\`var t: Str; t = a; str_len(t)\` — t's own header, a's copied (6.7.13 read a's string through the pun)"
row U2 'fn g(c): i64 { var t: Str; if (c == 1) { t = str_from("abc"); } else { t = str_from("de"); } return str_len(t); }
fn go(): i64 { return g(1); }'
runs U2 3 "\`var t: Str;\` assigned in one branch"

# --- D20: the filed repro (issues/archived/2026-10-15-str-handle-into-inline-str-stores-one-word.md), verbatim, and its rows ---
cat > "$T/D20a.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn main() {
    alloc_init();
    var a = str_from("abcde");
    var t: Str;
    t = a;
    return str_len(t);
}
var r = main();
syscall(SYS_EXIT, r);
EOF
runs D20a 5 "the filed repro: \`var t: Str; t = a; str_len(t)\` (5 through t's own header)" "$XLEGS $OLEGS"
sed 's/return str_len(t);/return t.len;/' "$T/D20a.cyr" > "$T/D20b.cyr"
runs D20b 5 "the filed repro's \`return t.len;\` (the pun left t.len unwritten)" "$XLEGS $OLEGS"
row D20c 'fn go(): i64 { var t: Str; t = str_from("hello"); var h: Str = Str { "zz", 2 }; h = t; return str_len(h); }'
runs D20c 5 "the filed row 3: \`h = t\` copies t's header, a's copied into t (6.7.13: t's unwritten length)"

# --- D18: the filed repro (issues/archived/2026-10-15-inline-str-into-untyped-or-other-pointer-position-passes-data-word.md), verbatim ---
cat > "$T/D18a.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fnptr.cyr"
fn f(s: Str): i64 { return str_len(s); }
fn main() {
    alloc_init();
    var t: Str = Str { "abcdefg", 7 };
    var h = str_from("abcdefg");
    return h.eq(t);          # Str_eq(self, other): `other` is untyped
}
var r = main();
syscall(SYS_EXIT, r);
EOF
runs D18a 1 "the filed repro: \`h.eq(t)\` — Str_eq's \`other: Str\` takes t's header (was 0)" "$XLEGS $OLEGS"
row D18b 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var p: *Str = t; return str_len(p); }'
runs D18b 7 "the filed table's \`var p: *Str = t; str_len(p)\` (was the data word)"
# D18c: `var p: *Str = gt;` is the header's address, so it is not warned "assigning non-pointer to typed pointer"
# (6.7.13 warned: the factor leaves an inline global's scale 0).
row D18c 'fn go(): i64 { var p: *Str = gt; return str_len(p); }'
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" D18c
    if [ "$crc" -ne 0 ] || [ ! -s "$T/D18c.$leg" ]; then bad "D18c ($leg): did not build (rc $crc)"
    elif grep -q '^warning' "$T/D18c.$leg.err"; then bad "D18c ($leg): warned: $(grep '^warning' "$T/D18c.$leg.err" | head -1)"
    else ok "D18c \`var p: *Str = gt;\` ($leg): no warning"; fi
done
runs D18c 7 "\`var p: *Str = gt;\` takes gt's static address"

# --- D16: the filed repro (issues/archived/2026-10-17-inline-str-assigned-into-str-pointer-keeps-data-word.md), verbatim ---
cat > "$T/D16a.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
var gt: Str = Str { "abcdefg", 7 };
var GP: *Str = 0;
fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var p: *Str = 0; p = t; return str_len(p); }
fn main(): i64 { alloc_init(); return go(); }
var r = main();
syscall(SYS_EXIT, r);
EOF
runs D16a 7 "the filed repro: \`p = t;\` into a \`*Str\` takes t's header (was 0, the data word)" "$XLEGS $OLEGS"
# D16b: the filed table's `GP = gt;` (and `p = gt;`) is the header's address, typed as the pointer: no warning.
row D16b 'var GP: *Str = 0;
fn go(): i64 { GP = gt; var p: *Str = 0; p = gt; return str_len(GP) * 10 + str_len(p); }'
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" D16b
    if [ "$crc" -ne 0 ] || [ ! -s "$T/D16b.$leg" ]; then bad "D16b ($leg): did not build (rc $crc)"
    elif grep -q '^warning' "$T/D16b.$leg.err"; then bad "D16b ($leg): warned: $(grep '^warning' "$T/D16b.$leg.err" | head -1)"
    else ok "D16b \`GP = gt; p = gt;\` ($leg): no warning"; fi
done
runs D16b 77 "\`GP = gt; p = gt;\` take gt's static address (was 0)"

# --- SD1: the filed repro (issues/archived/2026-10-17-str-pointer-dereference-into-str-parameter-passes-data-word.md), verbatim ---
cat > "$T/SD1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
fn main(): i64 {
    alloc_init();
    var h = str_from("abcde");
    var p: *Str = h;
    var pp: **Str = &p;
    var s1: Str = *p;
    var s2: Str = **pp;
    fmt_int(str_len(s1)); fmt_int(str_len(s2)); fmt_int(str_len(*p)); fmt_int(str_len(**pp));
    return 0;
}
syscall(60, main());
EOF
rows=$((rows + 1))
for leg in $XLEGS $OLEGS; do
    compile "$leg" SD1
    if [ "$crc" -ne 0 ] || [ ! -s "$T/SD1.$leg" ]; then bad "SD1 ($leg): did not build (rc $crc): $(grep '^error' "$T/SD1.$leg.err" | head -1 || true)"; continue; fi
    execute "$leg" SD1
    if [ "$got" -eq 0 ] && [ "$last" = "5555" ]; then ok "SD1 the filed repro: str_len(*p) / str_len(**pp) pass the header ($leg): $last"
    else bad "SD1 ($leg): exit $got, prints '$last' (want 5555; 5500 = the data word passed as the header)"; fi
done
# --- SD2: the filed repro (issues/archived/2026-10-18-generic-str-instance-dereference-argument-passes-data-word.md), verbatim:
# `gg<Str>(*p)` / `gg(*p)` into a generic's `x: T` at T = Str (address-passed) pass the header p points at (6.7.16; the
# header's data word through 6.7.15: 500 % 256 = 244) ---
cat > "$T/SD2.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn gg<T>(x: T): i64 { return str_len(x); }
fn f(s: Str): i64 { return str_len(s); }
fn main(): i64 {
    alloc_init();
    var h = str_from("abcde");
    var p: *Str = h;
    return f(*p) * 100 + gg<Str>(*p) * 10 + gg(*p);
}
var r = main();
syscall(SYS_EXIT, r);
EOF
runs SD2 43 "the filed repro: f(*p) / gg<Str>(*p) / gg(*p) pass the header (555 % 256; was 244, the data word into the generic)" "$XLEGS $OLEGS"

# --- D14: the filed repro (issues/archived/2026-10-17-inline-str-assigned-from-str-pointer-or-if-expression-stores-one-word.md), verbatim ---
cat > "$T/D14a.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str): i64 { return str_len(s); }
fn main(): i64 {
    alloc_init();
    var a = str_from("abcde");
    var p: *Str = a;
    var t: Str = Str { "zz", 2 };
    t = p;
    return t.len * 10 + f(t);
}
var r = main();
syscall(SYS_EXIT, r);
EOF
runs D14a 55 "the filed repro: \`t = p;\` (p a \`*Str\`) copies the header into an inline Str (was 22: t.data = p, t.len stale)" "$XLEGS $OLEGS"
# D14b: the filed table's `t = *p;` copies too, with no "assigning non-pointer to typed pointer" (it warned).
sed 's/^    t = p;$/    t = *p;/' "$T/D14a.cyr" > "$T/D14b.cyr"
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" D14b
    if [ "$crc" -ne 0 ] || [ ! -s "$T/D14b.$leg" ]; then bad "D14b ($leg): did not build (rc $crc)"
    elif grep -q '^warning' "$T/D14b.$leg.err"; then bad "D14b ($leg): warned: $(grep '^warning' "$T/D14b.$leg.err" | head -1)"
    else ok "D14b \`t = *p;\` ($leg): no warning"; fi
done
runs D14b 55 "the filed table's \`t = *p;\` copies the header (was 22)" "$XLEGS $OLEGS"
# D15: the filed table's if-expression of Str handles keeps the one-word store — t.data = the chosen handle, t.len stale
# (22) — with today's warning (the user's decision D15, 2026-10-18: documented, unchanged).
sed 's/^    t = p;$/    var c = 1;\n    t = if (c == 1) { a } else { a };/' "$T/D14a.cyr" > "$T/D15.cyr"
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" D15
    if [ "$crc" -ne 0 ] || [ ! -s "$T/D15.$leg" ]; then bad "D15 ($leg): did not build (rc $crc)"
    elif ! grep -q '^warning.*assigning non-pointer to typed pointer' "$T/D15.$leg.err"; then bad "D15 ($leg): today's warning is gone: $(grep -E '^(warning|error)' "$T/D15.$leg.err" | head -1 || true)"
    else ok "D15 \`t = if (c == 1) { a } else { a };\` ($leg): compiles with today's warning"; fi
done
runs D15 22 "an if-expression of Str handles keeps the one-word store (D15: documented, 22 as before)" "$XLEGS $OLEGS"

# --- PP1: the filed repro (issues/archived/2026-10-18-inline-str-from-double-str-pointer-single-deref-stores-one-word.md), verbatim:
# `t = *pp` (pp a `**Str`) copies the header the `*Str` *pp reads points at (6.7.16; 22 through 6.7.15), no warning ---
cat > "$T/PP1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str): i64 { return str_len(s); }
fn main(): i64 {
    alloc_init();
    var a = str_from("abcde");
    var p: *Str = a;
    var pp: **Str = &p;
    var t: Str = Str { "zz", 2 };
    t = *pp;
    return t.len * 10 + f(t);
}
var r = main();
syscall(SYS_EXIT, r);
EOF
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" PP1
    if [ "$crc" -ne 0 ] || [ ! -s "$T/PP1.$leg" ]; then bad "PP1 ($leg): did not build (rc $crc)"
    elif grep -q '^warning' "$T/PP1.$leg.err"; then bad "PP1 ($leg): warned: $(grep '^warning' "$T/PP1.$leg.err" | head -1)"
    else ok "PP1 \`t = *pp;\` ($leg): no warning"; fi
done
runs PP1 55 "the filed repro: \`t = *pp;\` (pp a \`**Str\`) copies the header into an inline Str (was 22: t.data = *pp, t.len stale)" "$XLEGS $OLEGS"

# --- HD1: the filed repro (issues/archived/2026-10-18-str-handle-assigned-str-pointer-dereference-stores-data-word.md), verbatim:
# `h = *p` into a Str handle (p a `*Str`) rebinds h to the header p points at (6.7.16, D20; through 6.7.15 the header's
# data word, str_len 0, and a false "assigning non-pointer to typed pointer"), no warning ---
cat > "$T/HD1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn main(): i64 {
    alloc_init();
    var a = str_from("abcde");
    var p: *Str = a;
    var h = str_from("zz");
    h = *p;
    return str_len(h);
}
var r = main();
syscall(SYS_EXIT, r);
EOF
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" HD1
    if [ "$crc" -ne 0 ] || [ ! -s "$T/HD1.$leg" ]; then bad "HD1 ($leg): did not build (rc $crc)"
    elif grep -q '^warning' "$T/HD1.$leg.err"; then bad "HD1 ($leg): warned: $(grep '^warning' "$T/HD1.$leg.err" | head -1)"
    else ok "HD1 \`h = *p;\` ($leg): no warning"; fi
done
runs HD1 5 "the filed repro: \`h = *p;\` into a Str handle rebinds it to the header p points at (D20; was 0, the data word)" "$XLEGS $OLEGS"

# --- HF1: the filed repro (issues/archived/2026-10-19-str-field-assigned-str-pointer-dereference-stores-data-word.md), verbatim:
# `w.s = *p` / `GW.s = *p` into a `Str` FIELD (p a `*Str`) is p, as `v.s = p` is (6.7.16; through 6.7.15 the header's
# data word: `160111`, exit 50), no warning ---
cat > "$T/HF1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
struct WS { s: Str; n; }
var GW: WS = WS { 0, 0 };
fn main(): i64 {
    alloc_init();
    var a = str_from("abcde");
    var p: *Str = a;
    var w: WS = WS { str_from("zz"), 1 };
    var v: WS = WS { str_from("zz"), 1 };
    w.s = *p;
    v.s = p;
    GW.s = *p;
    fmt_int(sizeof(WS)); fmt_int(w.s == a); fmt_int(w.s == load64(a)); fmt_int(v.s == a); fmt_int(GW.s == load64(a));
    return str_len(w.s) * 100 + str_len(v.s) * 10 + str_len(GW.s);
}
var r = main();
syscall(SYS_EXIT, r % 256);
EOF
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" HF1
    if [ "$crc" -ne 0 ] || [ ! -s "$T/HF1.$leg" ]; then bad "HF1 ($leg): did not build (rc $crc)"
    elif grep -q '^warning' "$T/HF1.$leg.err"; then bad "HF1 ($leg): warned: $(grep '^warning' "$T/HF1.$leg.err" | head -1)"
    else ok "HF1 \`w.s = *p;\` ($leg): no warning"; fi
done
rows=$((rows + 1))
for leg in $XLEGS $OLEGS; do
    compile "$leg" HF1
    if [ "$crc" -ne 0 ] || [ ! -s "$T/HF1.$leg" ]; then bad "HF1 ($leg): did not build (rc $crc)"; continue; fi
    execute "$leg" HF1
    if [ "$got" = 43 ] && [ "$last" = 161010 ]; then ok "HF1 the filed repro ($leg): '$last', exit 43"
    else bad "HF1 the filed repro ($leg): '$last', exit $got (want '161010', exit 43: w.s and GW.s are p)"; fi
done

# --- PL1-PL3: the filed repros (issues/archived/2026-10-19-struct-literal-str-pointer-field-from-inline-str-stores-data-word.md):
# a struct literal's `*Str` element from an inline `Str` takes its header's address, as `w.p = gt` does (6.7.16, D19;
# through 6.7.15 the data word: 0) — PL1 verbatim (7), PL3 the filed top-level line (7); a frame's `W { t, 1 }` is
# refused with the field's words, as `w.p = t` is (PL2 verbatim; it compiled, 0) — named (PL2b) and a nested struct's
# leaf (PL2c) too ---
cat > "$T/PL1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
var gt: Str = Str { "abcdefg", 7 };
struct W { p: *Str; n; }
fn go(): i64 { var w: W = W { gt, 1 }; return str_len(w.p); }
fn main(): i64 { alloc_init(); return go(); }
var r = main();
syscall(SYS_EXIT, r);
EOF
runs PL1 7 "the filed repro 1: \`W { gt, 1 }\` into a \`*Str\` field takes gt's header (was 0, the data word)" "$XLEGS $OLEGS"
cat > "$T/PL2.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct W { p: *Str; n; }
fn go(): i64 { var t: Str = Str { "abc", 3 }; var w: W = W { t, 1 }; return str_len(w.p); }
fn main(): i64 { alloc_init(); return go(); }
var r = main();
syscall(SYS_EXIT, r);
EOF
refused PL2 "$MF" "the filed repro 2: a frame's \`W { t, 1 }\` into a \`*Str\` field (D19; it compiled, the data word)"
row PL2b 'struct WP { p: *Str; n; }
fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: WP = WP { n: 1, p: (t) }; return str_len(w.p); }'
refused PL2b "$MF" "\`WP { n: 1, p: (t) }\`, named"
row PL2c 'struct WP2 { n; p: *Str; }
struct OP2 { k; w: WP2; }
fn go(): i64 { var t: Str; var o: OP2 = OP2 { 5, 1, t }; return str_len(o.w.p); }'
refused PL2c "$MF" "\`OP2 { 5, 1, t }\`, a nested struct's \`*Str\` leaf, of a bare \`var t: Str;\`"
cat > "$T/PL3.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
var gt: Str = Str { "abcdefg", 7 };
struct W { p: *Str; n; }
var GW: W = W { gt, 1 };
fn main(): i64 { alloc_init(); return str_len(GW.p); }
var r = main();
syscall(SYS_EXIT, r);
EOF
runs PL3 7 "the filed top-level line: a zone \`var GW: W = W { gt, 1 };\` (was 0)" "$XLEGS $OLEGS"

# --- PD1: the filed repro (issues/archived/2026-10-19-str-declaration-from-double-str-pointer-single-deref-binds-handle.md),
# verbatim: `var u: Str = *pp;` (pp a `**Str`) is u's own copy of the header, as `var v: Str = p;` is (6.7.16, the
# user's D74, 2026-10-20; through 6.7.15 a handle on it: 15) ---
cat > "$T/PD1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str): i64 { return str_len(s); }
fn main(): i64 {
    alloc_init();
    var a = str_from("abcde");
    var p: *Str = a;
    var pp: **Str = &p;
    var u: Str = *pp;
    var v: Str = p;
    a.len = 1;
    return u.len * 10 + f(v);
}
var r = main();
syscall(SYS_EXIT, r);
EOF
runs PD1 55 "the filed repro: \`var u: Str = *pp;\` is u's own copy (D74; was 15, a handle)" "$XLEGS $OLEGS"

# --- DS1: the filed repro (issues/archived/2026-10-19-store-through-str-pointer-from-str-pointer-dereference-stores-data-word.md),
# verbatim: `*q = *p` (q, p `*Str`) stores p — q's first word becomes the header's address, as `*q = *pp` and `*q = gt`
# store (6.7.16, the user's D73, 2026-10-20; through 6.7.15 the header's data word: `21020121`), no warning ---
cat > "$T/DS1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
var gt: Str = Str { "abcdefg", 7 };
fn main(): i64 {
    alloc_init();
    var a = str_from("abcde");
    var p: *Str = a;
    var pp: **Str = &p;
    var b = str_from("xy");
    var q: *Str = b;
    *q = *p;
    fmt_int(str_len(q)); fmt_int(load64(q) == load64(a)); fmt_int(load64(q) == a);
    var c = str_from("uv");
    var r: *Str = c;
    *r = *pp;
    fmt_int(str_len(r)); fmt_int(load64(r) == load64(a)); fmt_int(load64(r) == a);
    var d = str_from("st");
    var s: *Str = d;
    *s = gt;
    fmt_int(str_len(s)); fmt_int(load64(s) == &gt);
    return 0;
}
syscall(60, main());
EOF
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" DS1
    if [ "$crc" -ne 0 ] || [ ! -s "$T/DS1.$leg" ]; then bad "DS1 ($leg): did not build (rc $crc)"
    elif grep -q '^warning' "$T/DS1.$leg.err"; then bad "DS1 ($leg): warned: $(grep '^warning' "$T/DS1.$leg.err" | head -1)"
    else ok "DS1 \`*q = *p;\` ($leg): no warning"; fi
done
rows=$((rows + 1))
for leg in $XLEGS $OLEGS; do
    compile "$leg" DS1
    if [ "$crc" -ne 0 ] || [ ! -s "$T/DS1.$leg" ]; then bad "DS1 ($leg): did not build (rc $crc)"; continue; fi
    execute "$leg" DS1
    if [ "$got" = 0 ] && [ "$last" = 20120121 ]; then ok "DS1 the filed repro ($leg): '$last'"
    else bad "DS1 the filed repro ($leg): '$last', exit $got (want '20120121', exit 0: q's first word is p)"; fi
done

# --- AMP1: the filed repro (issues/archived/2026-10-19-dereference-of-address-of-inline-str-reads-data-word.md), verbatim: `*(&t)`
# of an inline `Str` is t (6.7.16, the user's D71, 2026-10-20) — `var h: Str = *(&t);` a handle on t, `f(*(&t))`, `u =
# *(&t)` a copy, `k = *(&t)` a rebind: `3 3 3`, exit 3, no warning (through 6.7.15 `0 0 1`, exit 0, and two false
# "assigning non-pointer to typed pointer") ---
cat > "$T/AMP1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
fn f(s: Str): i64 { return str_len(s); }
fn main(): i64 {
    alloc_init();
    var t: Str = Str { "xyz", 3 };
    var h: Str = *(&t);
    fmt_int(str_len(h)); syscall(SYS_WRITE, 1, " ", 1);
    fmt_int(f(*(&t))); syscall(SYS_WRITE, 1, " ", 1);
    var u: Str = Str { "q", 1 };
    u = *(&t);
    fmt_int(u.len); syscall(SYS_WRITE, 1, "\n", 1);
    var k = str_from("q");
    k = *(&t);
    return str_len(k);
}
var r = main();
syscall(SYS_EXIT, r);
EOF
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" AMP1
    if [ "$crc" -ne 0 ] || [ ! -s "$T/AMP1.$leg" ]; then bad "AMP1 ($leg): did not build (rc $crc)"
    elif grep -q '^warning' "$T/AMP1.$leg.err"; then bad "AMP1 ($leg): warned: $(grep '^warning' "$T/AMP1.$leg.err" | head -1)"
    else ok "AMP1 \`u = *(&t);\` / \`k = *(&t);\` ($leg): no warning"; fi
done
rows=$((rows + 1))
for leg in $XLEGS $OLEGS; do
    compile "$leg" AMP1
    if [ "$crc" -ne 0 ] || [ ! -s "$T/AMP1.$leg" ]; then bad "AMP1 ($leg): did not build (rc $crc)"; continue; fi
    execute "$leg" AMP1
    if [ "$got" = 3 ] && [ "$last" = "3 3 3" ]; then ok "AMP1 the filed repro ($leg): '$last', exit 3"
    else bad "AMP1 the filed repro ($leg): '$last', exit $got (want '3 3 3', exit 3: *(&t) is t)"; fi
done

# --- FD1 / FD2: the filed repros (issues/archived/2026-10-18-inline-str-into-str-pointer-field-or-double-pointer-keeps-data-word.md),
# verbatim: an inline `Str` global into a `*Str` field (a local's, a global's, through a `*W`) and through a `**Str` takes
# its header's address (6.7.16, D19; through 6.7.15 the data word: 0 and 0) ---
cat > "$T/FD1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
var gt: Str = Str { "abcdefg", 7 };
struct W { p: *Str; n; }
var GW: W = W { 0, 0 };
fn go(): i64 { var w: W = W { 0, 1 }; w.p = gt; GW.p = gt; var pw: *W = &w; pw.p = gt; return str_len(w.p) * 100 + str_len(GW.p) * 10 + str_len(pw.p); }
fn main(): i64 { alloc_init(); return go(); }
var r = main();
syscall(SYS_EXIT, r);
EOF
runs FD1 9 "the filed repro 1: \`w.p = gt; GW.p = gt; pw.p = gt;\` into a \`*Str\` field (777 % 256; was 0, the data word)" "$XLEGS $OLEGS"
cat > "$T/FD2.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
var gt: Str = Str { "abcdefg", 7 };
struct W { p: *Str; n; }
fn go(): i64 { var q: *Str = 0; var pp: **Str = &q; *pp = gt; return str_len(q); }
fn main(): i64 { alloc_init(); return go(); }
var r = main();
syscall(SYS_EXIT, r);
EOF
runs FD2 7 "the filed repro 2: \`*pp = gt;\` through a \`**Str\` (was 0, the data word)" "$XLEGS $OLEGS"

# --- D21 / D22: the filed repros 1 and 2 (issues/archived/2026-10-15-top-level-str-declaration-from-inline-str-global-copies.md), verbatim ---
cat > "$T/D21a.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
var gt: Str = Str { "abcdefg", 7 };
var H: Str = gt;
fn main() { H.len = 3; return f(H) * 10 + gt.len; }
var r = main();
syscall(SYS_EXIT, r);
EOF
runs D21a 33 "the filed repro 1: a zone \`var H: Str = gt;\` binds gt's header (was 37, a copy)" "$XLEGS $OLEGS"
sed 's/^var H: Str = gt;$/alloc_init();\nvar H: Str = gt;/' "$T/D21a.cyr" > "$T/D21b.cyr"
runs D21b 33 "the same after a first top-level statement (was 37)" "$XLEGS $OLEGS"
# D21c: the D17 filed repro (issues/2026-10-17-toplevel-str-handle-from-inline-str-global-declared-below-refused-as-copy-
# init.md), verbatim — gt declared BELOW H binds as above (6.7.15, D17; refused "cannot copy-init" through 6.7.14).
cat > "$T/D21c.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
var H: Str = gt;
var gt: Str = Str { "abcdefg", 7 };
fn main() { H.len = 3; return f(H) * 10 + gt.len; }
var r = main();
syscall(SYS_EXIT, r);
EOF
runs D21c 33 "the D17 filed repro: a zone \`var H: Str = gt;\` with gt declared below binds gt's header (was refused)" "$XLEGS $OLEGS"
cat > "$T/D22a.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
var gt: Str = Str { "abcdefg", 7 };
var H = gt;
fn main() { return f(H); }
var r = main();
syscall(SYS_EXIT, r);
EOF
runs D22a 0 "the filed repro 2: an untyped top-level \`var H = gt;\` keeps gt's first word (D22 (b), unchanged)" "$XLEGS $OLEGS"
sed 's/^fn main() { return f(H); }$/fn main() { if (H == load64(\&gt)) { return 1; } return 2; }/' "$T/D22a.cyr" > "$T/D22b.cyr"
runs D22b 1 "\`var H = gt;\` at top level is gt's first word (H == load64(&gt))"

# --- SH: 6.7.17 (the user's D18, 2026-10-22) a struct value of another type into a `Str` HANDLE is refused by name, with
# the words the same assignment into a `P` handle has; it stored the struct's first word as the header's address
# (SIGSEGV at the next str_len). A handle, a `*T` or a `Str` value keeps its rebind (the SHK controls). ---
cat > "$T/SH1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct Q1 { a; }
fn mkq(): Q1 { var q: Q1; q.a = 5; return q; }
fn main(): i64 { alloc_init(); var h: Str = str_from("x"); h = mkq(); return str_len(h); }
syscall(60, main());
EOF
MSH="cannot copy 'mkq' into a variable of a different struct/vector type: 'h'"
refused SH1 "$MSH" "the D18 filed repro, verbatim (x86_64 139, cx 252, PE 5: h took Q1's word)"
HQ='struct Q1 { a; }
struct Q2 { a; b; }
struct WQ { q: Q1; pq: *Q1; n; }
fn mkq(): Q1 { var q: Q1; q.a = 5; return q; }
fn mkq2(): Q2 { var q: Q2; q.a = 5; q.b = 6; return q; }
fn gpq(): *Q1 { return alloc(8); }
impl Q1 { fn mk(self): Q1 { var q: Q1; q.a = 5; return q; } }
fn Q1_add(a: Q1, b: Q1): Q1 { var q: Q1; q.a = a.a + b.a; return q; }
var GQ: Q1 = Q1 { 5 };'
row SH2 "$HQ"'
fn go(): i64 { var h: Str = str_from("x"); h = mkq2(); return str_len(h); }'
refused SH2 "cannot copy 'mkq2' into a variable of a different struct/vector type: 'h'" "a 16-byte struct result"
row SH3 "$HQ"'
fn g(h: Str): i64 { h = mkq(); return str_len(h); }
fn go(): i64 { return g(str_from("x")); }'
refused SH3 "$MSH" "into a \`Str\` parameter"
row SH4 "$HQ"'
fn go(): i64 { G = str_from("x"); G = mkq(); return str_len(G); }'
refused SH4 "cannot copy 'mkq' into a variable of a different struct/vector type: 'G'" "into a \`Str\` global"
row SH5 "$HQ"'
fn go(): i64 { var q: Q1; var h: Str = str_from("x"); h = q.mk(); return str_len(h); }'
refused SH5 "cannot copy 'Q1.mk' into a variable of a different struct/vector type: 'h'" "a method result"
row SH6 "$HQ"'
fn go(): i64 { var q: Q1; var h: Str = str_from("x"); h = q + q; return str_len(h); }'
refused SH6 "cannot copy 'Q1_add' into a variable of a different struct/vector type: 'h'" "an operator result"
row SH7 "$HQ"'
fn go(): i64 { var c = 1; var h: Str = str_from("x"); h = if (c == 1) { mkq() } else { mkq() }; return str_len(h); }'
refused SH7 "cannot copy 'Q1' into a variable of a different struct/vector type: 'h'" "an if-expression of struct results"
row SH8 "$HQ"'
fn go(): i64 { var q: Q1; var h: Str = str_from("x"); h = q; return str_len(h); }'
refused SH8 "cannot copy 'q' into a variable of a different struct/vector type: 'h'" "an inline struct name"
row SH9 "$HQ"'
fn go(): i64 { var h: Str = str_from("x"); h = (GQ); return str_len(h); }'
refused SH9 "cannot copy 'GQ' into a variable of a different struct/vector type: 'h'" "a wrapped inline struct global"
row SH10 "$HQ"'
fn go(): i64 { var q: Q1; var w: WQ; w.pq = &q; var h: Str = str_from("x"); h = *w.pq; return str_len(h); }'
refused SH10 "cannot copy '*w.pq' into a variable of a different struct/vector type: 'h'" "a dereference of a \`*Q1\`"
row SH11 "$HQ"'
fn go(): i64 { var h: Str = str_from("x"); var i = 0; for (i = 0; i < 1; h = (mkq())) { i = i + 1; } return str_len(h); }'
refused SH11 "$MSH" "a for step, wrapped"
row SH12 "$HQ"'
fn go(): i64 { var h = str_from("x"); h = fncall0(&mkq); return str_len(h); }'
refused SH12 "cannot copy 'mkq' into a variable of a different struct/vector type: 'h'" "an untyped \`var h = str_from(..)\` (a \`Str\`) from \`fncall0(&mkq)\`"
row SH13 "$HQ"'
fn go(): i64 { var t: Str = Str { "ab", 2 }; var p: *Str = &t; p = mkq(); return str_len(p); }'
refused SH13 "cannot copy 'mkq' into a variable of a different struct/vector type: 'p'" "into a \`*Str\` local"
cat > "$T/SH14.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct Q1 { a; }
fn mkq(): Q1 { var q: Q1; q.a = 5; return q; }
alloc_init();
var GH: Str = str_from("x");
GH = mkq();
syscall(60, str_len(GH));
EOF
refused SH14 "cannot copy 'mkq' into a variable of a different struct/vector type: 'GH'" "at top level"
row SH15 "$HQ"'
fn go(): i64 { var w: WQ; var h: Str = str_from("x"); h = w.q; return str_len(h); }'
refused SH15 "cannot copy 'q' into a variable of a different struct/vector type: 'h'" "a struct-typed field"
row SHK1 "$HQ"'
fn go(): i64 { var q: Q1; var pq: *Q1 = &q; var hq: Q2 = alloc(16); var h: Str = str_from("x"); h = pq; var a = 0; if (h == pq) { a = 1; } h = hq; if (h == hq) { a = a + 2; } h = gpq(); if (h != 0) { a = a + 4; } h = str_from("abc"); return a * 10 + str_len(h); }'
runs SHK1 73 "controls: a \`*Q1\`, a \`Q2\` handle and a \`: *Q1\` call rebind a \`Str\` handle; a \`: Str\` call is its value"
# --- SP: 6.7.17 (D18 at every `Str` slot) a struct value of another type into a `Str` FIELD (a local's, a global's,
# through a `*W`, a for step, top level), a literal's `Str` element, a store through a `*Str` / `**Str`, and `return` from a
# fn returning `Str` (a tail call too) is refused with the position's words, as into a `P`; each stored or returned the
# struct's first word as the header's address. Controls in SPK1. ---
MSF="cannot copy 'mkq' into a struct field of a different struct type: 's'"
row SP1 "$HQ"'
fn go(): i64 { var w: W = W { 0, 1 }; w.s = mkq(); return f(w.s); }'
refused SP1 "$MSF" "\`w.s = mkq();\` into a local's \`Str\` field"
row SP2 "$HQ"'
var GW: W = W { 0, 0 };
fn go(): i64 { var q: Q1; GW.s = (q); return 0; }'
refused SP2 "cannot copy 'q' into a struct field of a different struct type: 's'" "\`GW.s = (q);\` into a global's"
row SP3 "$HQ"'
fn go(): i64 { var q: Q1; var pq: *Q1 = &q; var p: *W = new_w(); p.s = *pq; return 0; }'
refused SP3 "cannot copy '*pq' into a struct field of a different struct type: 's'" "\`p.s = *pq;\` through a \`*W\`"
row SP4 "$HQ"'
fn go(): i64 { var w: W = W { 0, 1 }; var x: WQ; var i = 0; for (i = 0; i < 1; w.s = x.q) { i = i + 1; } return 0; }'
refused SP4 "cannot copy 'q' into a struct field of a different struct type: 's'" "a for step's \`w.s = x.q\`"
row SP5 "$HQ"'
fn go(): i64 { var q: Q1; var w: W = W { q.mk(), 1 }; return f(w.s); }'
refused SP5 "cannot copy 'Q1.mk' into a struct field of a different struct type: 's'" "\`W { q.mk(), 1 }\`, a literal's \`Str\` element"
cat > "$T/SP6.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct Q1 { a; }
struct W { s: Str; n; }
fn mkq(): Q1 { var q: Q1; q.a = 5; return q; }
var GW = W { mkq(), 1 };
GW.s = mkq();
syscall(60, str_len(GW.s));
EOF
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" SP6
    if [ "$crc" -ne 0 ] && [ "$(grep -c "^error.*$MSF" "$T/SP6.$leg.err")" -eq 2 ] && [ "$(grep -c '^error\|^warning' "$T/SP6.$leg.err")" -eq 2 ] && [ ! -s "$T/SP6.$leg" ]; then ok "SP6 top level: a zone literal's element and a field store, both refused ($leg)"
    else bad "SP6 top level ($leg): rc $crc: $(grep '^error\|^warning' "$T/SP6.$leg.err" | tr '\n' '|')"; fi
done
row SP7 "$HQ"'
fn go(): i64 { var q: Q1; var ps: *Str = new_slot(); *ps = q; return 0; }'
refused SP7 "cannot copy 'q' into a variable of a different struct/vector type: 'ps'" "\`*ps = q;\` through a \`*Str\`"
row SP8 "$HQ"'
fn go(): i64 { var h: Str = str_from("x"); var p: *Str = &h; var pp: **Str = &p; **pp = mkq(); return 0; }'
refused SP8 "cannot copy 'mkq' into a variable of a different struct/vector type: 'pp'" "\`**pp = mkq();\` through a \`**Str\`"
row SP9 "$HQ"'
fn r(): Str { return mkq(); }
fn go(): i64 { return f(r()); }'
refused SP9 "a fn returning the struct \`Str\` takes a value of that struct, or a pointer to one — got \`mkq\` (a \`Q1\`)" "\`return mkq();\` (a tail call) from a fn returning \`Str\`"
row SP10 "$HQ"'
fn r(pq: *Q1): Str { return (*pq); }
fn go(): i64 { var q: Q1; return f(r(&q)); }'
refused SP10 "a fn returning the struct \`Str\` takes a value of that struct, or a pointer to one — got \`*pq\` (a \`Q1\`)" "\`return (*pq);\` from a fn returning \`Str\`"
row SPK1 "$HQ"'
fn r(): Str { return str_from("abcd"); }
fn go(): i64 { var w: W = W { str_from("ab"), 1 }; w.s = str_from("abc"); var w2: W = W { w.s, 2 }; var h: Str = str_from("x"); var p: *Str = &h; *p = r(); var q: Q1; var pq: *Q1 = &q; w.s = pq; var a = 0; if (w.s == pq) { a = 1; } return a * 100 + str_len(w2.s) * 10 + str_len(h); }'
runs SPK1 134 "controls: a \`: Str\` call / field into a \`Str\` field and a literal, through a \`*Str\`, a \`*Q1\` rebinding a field"
# --- NS: 6.7.17 (the user's D19, 2026-10-22) `*p` of a `*Str` as a nested struct field's element reaching a `Str` first
# leaf is p, as the direct literal `WS { *p, 1 }` stores it; it stored the header's data word (exit 50 on every target).
# A `Str` value off the field's first-leaf chain is refused by name, as a `Str` name there is (NS2). ---
cat > "$T/NS1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct WS { s: Str; n; }
struct O { v: WS; m; }
fn main(): i64 { alloc_init(); var a = str_from("abcdefg"); var p: *Str = a; var o = O { *p, 1, 2 }; if (o.v.s == a) { return 10; } if (o.v.s == load64(a)) { return 50; } return 99; }
syscall(60, main());
EOF
runs NS1 10 "the D19 filed repro, verbatim (was 50: the header's data word)" "$XLEGS $OLEGS"
row NS2 'struct WI { n; m; }
struct O2 { v: WI; k; }
fn go(): i64 { var a = str_from("abcdefg"); var p: *Str = a; var o = O2 { *p, 1, 2 }; return o.k; }'
refused NS2 "cannot copy '*p' into a struct field of a different struct type: 'v'" "\`O2 { *p, 1, 2 }\`: a \`Str\` value off the first-leaf chain (it carried the data word into v.n)"
# NS3 / NS4 (6.7.17, met in the D19 bite): `*(&t)` of an inline `Str` is t (6.7.16's D71), so as a nested element it is
# refused as `O { t, 1, 2 }` is, named at t; it carried t's data word into the field's first leaf, silently.
row NS3 'struct WS { s: Str; n; }
struct O { v: WS; m; }
fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var o = O { *(&t), 1, 2 }; return o.m; }'
refused NS3 "cannot copy 't' into a struct field of a different struct type: 'v'" "\`O { *(&t), 1, 2 }\` of a frame's t"
row NS4 'struct WS { s: Str; n; }
struct O { v: WS; m; }
fn go(): i64 { var o = O { (*&gt), 1, 2 }; return o.m; }'
refused NS4 "cannot copy 'gt' into a struct field of a different struct type: 'v'" "\`O { (*&gt), 1, 2 }\` of an inline global"
# --- CA: 6.7.17 (the user's D20, 2026-10-22) `*(&t) = v` with t a closure's captured inline `Str` copies v's header into
# the closure's copy of t, as `*(&t) = v` of a local t does (6.7.16's D71) and a captured struct's `*(&s) = v` does
# (6.7.13); it wrote v's first word into the copy's data word (exit 7). Another struct is refused as `t = mkq()` is (CA2). ---
cat > "$T/CA1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fnptr.cyr"
fn main(): i64 { alloc_init(); var t: Str = Str { "abcdefg", 7 }; var v = str_from("xy"); var f = |k| { *(&t) = v; return t.len + k; }; return fncall1(f, 0); }
syscall(60, main());
EOF
runs CA1 2 "the D20 filed repro, verbatim (was 7: v's word into the copy's data word)" "$XLEGS $OLEGS"
row CA2 'include "lib/fnptr.cyr"
struct Q1 { a; }
fn mkq(): Q1 { var q: Q1; return q; }
fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var f = |k| { *(&t) = mkq(); return t.len + k; }; return fncall1(f, 0); }'
refused CA2 "cannot copy 'mkq' into a variable of a different struct/vector type: 't'" "a closure's \`*(&t) = mkq();\` (it stored Q1's word)"
# CA3 (6.7.17, met in the D20 bite): a captured t's `*(&t) += 1` is refused as a local t's is (X29) and a captured
# struct's `*(&s) += 1` is; it stepped the copy's data word, silently.
row CA3 'include "lib/fnptr.cyr"
fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var f = |k| { *(&t) += 1; return t.len + k; }; return fncall1(f, 0); }'
refused CA3 "compound assignment to struct 't' is refused - a struct value is not an integer or a float (write \`a = a + b\`)" "a closure's \`*(&t) += 1\` of its captured t"
# --- NM: 6.7.17 (the user's D21, 2026-10-22) a `Str` field's NAMED initialiser compiles, as the positional `V { a, 1 }`
# does, with the same `Str` field checks; it was "named init not supported for nested struct fields — use positional". ---
cat > "$T/NM1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct V { s: Str; n; }
fn main(): i64 { alloc_init(); var a = str_from("abc"); var v = V { s: a, n: 1 }; return str_len(v.s) + v.n; }
syscall(60, main());
EOF
runs NM1 4 "the D21 filed repro, verbatim (was refused)" "$XLEGS $OLEGS"
row NM2 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: W = W { n: 1, s: t }; return f(w.s); }'
refused NM2 "$MF" "\`W { n: 1, s: t }\` of a frame's t: refused as would-dangle, as \`W { t, 1 }\` is"
row NM3 "$HQ"'
fn go(): i64 { var w: W = W { s: mkq(), n: 1 }; return f(w.s); }'
refused NM3 "$MSF" "\`W { s: mkq(), n: 1 }\`: another struct refused, as positionally (D18)"
# --- ZS: 6.7.17 (the user's D22, 2026-10-22) an untyped top-level `var bb = str_from("xyz");` is a `Str` (a handle
# global, its value unchanged), in the declaration zone and after the first statement, as in a fn; `bb.len` was "no struct
# type in scope for 'bb'". A name keeps its word (D22a / D22b above, 6.7.14's D22 (b)). ---
cat > "$T/ZS1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
alloc_init();
var bb = str_from("xyz");
syscall(60, bb.len);
EOF
runs ZS1 3 "the D22 filed repro, verbatim (was refused)" "$XLEGS $OLEGS"
cat > "$T/ZS2.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
var bb = str_from("xyz");
fn rd(): i64 { return bb.len; }
alloc_init();
syscall(60, rd());
EOF
runs ZS2 3 "the filed zone line: \`var bb = str_from(..);\` above a fn reading \`bb.len\`"

# --- CMP: a Str HANDLE passed to the five retyped methods compiles byte-identical to the untyped methods ---
rows=$((rows + 1))
cat > "$T/CMP.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn main(): i64 {
    alloc_init();
    var h = str_from("abcdefg");
    var k = str_from("cde");
    var n = h.eq(k) + h.contains(k) + h.starts_with(k) + h.ends_with(k);
    return n * 100 + str_len(h.cat(k));
}
var r = main();
syscall(SYS_EXIT, r);
EOF
mkdir -p "$T/untyped"
cp -r lib "$T/untyped/lib"
sed -i -e 's/^fn Str_eq(self, other: Str)/fn Str_eq(self, other)/' -e 's/^fn Str_cat(self, other: Str)/fn Str_cat(self, other)/' \
    -e 's/^fn Str_contains(self, needle: Str)/fn Str_contains(self, needle)/' \
    -e 's/^fn Str_starts_with(self, prefix: Str)/fn Str_starts_with(self, prefix)/' \
    -e 's/^fn Str_ends_with(self, suffix: Str)/fn Str_ends_with(self, suffix)/' "$T/untyped/lib/str.cyr"
if [ "$(grep -cE '^fn Str_(eq|cat|contains|starts_with|ends_with)\(self, [a-z]+\)' "$T/untyped/lib/str.cyr")" != 5 ]; then
    bad "CMP: the untyped copy of lib/str.cyr does not hold the five untyped methods (lib/str.cyr changed?)"
else
    for leg in x86_64 pe; do
        compile "$leg" CMP
        cp "$T/CMP.$leg" "$T/CMP.$leg.typed"
        crc2=0
        case $leg in
            x86_64) (cd "$T/untyped" && timeout 60 "$CC" < "$T/CMP.cyr" > "$T/CMP.$leg.untyped" 2> /dev/null) || crc2=$? ;;
            pe)     (cd "$T/untyped" && CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$T/CMP.cyr" > "$T/CMP.$leg.untyped" 2> /dev/null) || crc2=$? ;;
        esac
        if [ "$crc" -ne 0 ] || [ "$crc2" -ne 0 ]; then bad "CMP ($leg): did not build (rc $crc / $crc2)"
        elif cmp -s "$T/CMP.$leg.typed" "$T/CMP.$leg.untyped"; then ok "CMP ($leg): a handle into the typed methods builds byte-identical"
        else bad "CMP ($leg): the typed methods changed a handle argument's code"; fi
    done
    if [ "$QEMU" -eq 1 ]; then
        compile aarch64 CMP
        crc2=0; (cd "$T/untyped" && timeout 60 "$A64" < "$T/CMP.cyr" > "$T/CMP.a64.untyped" 2> /dev/null) || crc2=$?
        if [ "$crc" -eq 0 ] && [ "$crc2" -eq 0 ] && cmp -s "$T/CMP.aarch64" "$T/CMP.a64.untyped"; then ok "CMP (aarch64): byte-identical"
        else bad "CMP (aarch64): differs or did not build (rc $crc / $crc2)"; fi
    fi
    if [ "$CX" -eq 1 ]; then
        compile cx CMP
        crc2=0; (cd "$T/untyped" && timeout 60 "$CXC" < "$T/CMP.cyr" > "$T/CMP.cx.untyped" 2> /dev/null) || crc2=$?
        if [ "$crc" -eq 0 ] && [ "$crc2" -eq 0 ] && cmp -s "$T/CMP.cx" "$T/CMP.cx.untyped"; then ok "CMP (cx): byte-identical"
        else bad "CMP (cx): differs or did not build (rc $crc / $crc2)"; fi
    fi
fi
runs CMP 110 "the handle program runs: (eq 0 + contains 1 + starts 0 + ends 0) * 100 + the cat's 10" "x86_64"

# --- AS1: an inline Str in an async fn (the coroutine's heap frame), across awaits ---
if [ -f lib/async.cyr ]; then
    printf 'include "lib/alloc.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/fnptr.cyr"\ninclude "lib/str.cyr"\ninclude "lib/async.cyr"\nfn f(s: Str): i64 { return str_len(s); }\nasync fn job(x): i64 { return x; }\nasync fn outer(x): i64 {\n    var t: Str = Str { "abcdefg", 7 };\n    var u = await job(x);\n    var h: Str = t;\n    var v = await job(f(t));\n    return u * 100 + v * 10 + str_len(h);\n}\nfn main(): i64 {\n    alloc_init();\n    var C = outer(1);\n    var r = 0;\n    var n = 0;\n    while (n < 4) { r = future_force(C); n = n + 1; }\n    return r %% 256;\n}\nvar rr = main();\nsyscall(60, rr);\n' > "$T/AS1.cyr"
    runs AS1 177 "an async fn: f(t) and var h: Str = t across awaits (1*100 + 7*10 + 7)" "x86_64:CYRIUS_ASYNC=1"
else echo "  SKIP AS1: no lib/async.cyr"; skips=$((skips + 1)); fi

FLOOR_ROWS=127   # 6.7.17: + SH1-SH15, SHK1, SP1-SP10, SPK1 (D18), NS1, NS2 (D19), NS3, NS4, CA1, CA2 (D20), CA3, NM1-NM3 (D21), ZS1, ZS2 (D22); 6.7.16: + PP1 (2 rows), + HD1 (2 rows, D20), + X15-X19 / FD1 / FD2 (7 rows, D19), + SD2, + HF1 (2 rows), + PL1-PL3 (5 rows), + PD1 (D74), + DS1 (2 rows, D73), + X20-X29 / AMP1 (12 rows, D71), + X30 / X31; the floor is the count that runs
[ "$rows" -ge "$FLOOR_ROWS" ] || bad "only $rows rows ran (floor $FLOOR_ROWS) — rows were lost"
echo "  $rows rows, $fails failed, $skips skipped"
if [ "$fails" -ne 0 ]; then echo "FAIL: $G ($fails)"; exit 1; fi
echo "PASS: $G — an inline Str is its header's address where a Str value is taken; a frame's escaping it is refused by name"
