# `var u: Str = *pp;` (pp a `**Str`, so `*pp` is a `*Str`) binds u as a handle on the header, where `var u: Str = p;` copies it — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-10, `b0ee3bfe7` — D74 (the user, 2026-10-20: "Its own copy"); at top level 6.7.16's D17 (a) / D18 (a) ("a copy, at every size"). `_hl_dpp_str` answers a declaration's mode 1, so `_sci_dexpr` copies the header (the filing's scratch mutant); at top level `_gz_star` / `_gz_dx_init` / `_gci_dx_top` copy `*GPP` and `_gz_pnat_str` copies `GP`. The filed repro exits 55 (it was 15) on every leg; `(*pp)`, a parameter's, a capture's, `*GPPS`, `*gpps()`, `*w.pp`, `**ppp` the same; a top-level `var U: Str = *GPP;` / `var V: Str = GP;` copy (they bound a handle). Rows: `inline_str_value.sh` PD1 (the repro verbatim, seven legs); `crossos/inline_str_value.tcyr` pps_decl_* (controls: `var q: *Str = *pp;` and the untyped `var h = *pp;` stay the pointer) and R_TOP18; mutant t1 RED 14. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs lane (unit S1), beside
issues/archived/2026-10-18-inline-str-from-double-str-pointer-single-deref-stores-one-word.md (the ASSIGNMENT `t = *pp` copies
since that fix). Pre-existing: the same output on the slot-open compiler (480de63eb) and after the fix, on x86_64,
aarch64 (qemu) and cx (cxvm). Not that filing's surface (its table is the assignment; its own control line
"`var u: Str = *pp; t = u;` exits 55" reads u before the header changes, so the alias does not show), so filed, not fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; s16 lane, wave 4, unit SS2) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D74 — Its own copy.
**Severity:** Medium — silent: u aliases the header `*pp` points at (a later write through either is seen by the other),
where every other `*Str` source declaration copies it; no diagnostic. Not a security id (the developer's own source).
**Kind:** bug — the declaration twin of the filing above. A `Str` declaration in a fn copies the header from a `*Str`
name (`var u: Str = p;`), from `*p` and from `**pp` (6.7.14 / 6.7.15); `*pp` of a `**Str` is that same `*Str` (6.7.13's
D9 (a)), but the declaration does not read it as one.

## Reproduction

```cyrius
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
```

```
$ build/cycc < udecl.cyr > udecl && ./udecl; echo $?
15          # u.len 1 (u is a handle on a's header: a.len = 1 wrote it); v copied (5). Want 55.
```

aarch64 (qemu) and cx (cxvm) exit 15 too. Controls: `var u: Str = *p;` and `var u: Str = **pp;` give 55 in the same
program shape (copies).

## Root cause

A declaration's dereference source is `_sci_dexpr` (src/frontend/parse_decl.cyr), which asks `_hl_dstar_x(.., 1)`. Its
`**S` twin (`_hl_dpp_sid`) answers a plain struct in mode 1; `Str` is answered only in the assignment's mode 2
(`_hl_dpp_str`, 6.7.16). So `var u: Str = *pp;` falls to the scalar initialiser and u's slot takes the `*Str` `*pp`
reads: a handle on the header.

## Fix direction

Let the declaration copy from `*pp` of a `**Str` as it copies from `p`: `_sci_dexpr` asks mode 2 (or a declaration mode
that answers `Str`) and copies the 16-byte header through the `*Str` `_hl_dx_src` parks, as `_istr_dxa` does for the
assignment. Measured on a scratch mutant (mode 1 answering `Str` too): the repro gives 55. It changes what yesterday's
program does (an alias becomes a copy), so it is a behaviour change to record in the CHANGELOG / ecosystem-migration.md.
Rows beside tests/tcyr/crossos/inline_str_value.tcyr's pps_* rows (a local, `(*pp)`, a parameter, a capture).
