# The native-region renumber warning does not judge a fn-local `const` declared inside a region — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 platform lane's tree (l6714-platform, unit P2, after the
native-region fix for issues/archived/2026-10-15-native-region-warning-misses-included-files-and-author-constants.md), with the
ELF-aarch64 cross compiler built from it, run under qemu-aarch64.
**Placement:** 6.7.15 — repair 5 (platform lane, wave 1, unit P3; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — the wrong syscall runs with no diagnostic (the class the 6.7.12 / 6.7.14 warning exists for), in a
shape narrower than the two fixed ones: a `const` declared INSIDE a fn body that sits in a native-aarch64 region.
Warn-only territory (6.7.12's D1): no program's behaviour is at stake, only the missing warning. Workaround: the
`1000 + N` private alias, or declare the constant at top level (judged since 6.7.14).
**Affects:** ELF-aarch64 output; `src/backend/aarch64/emit.cyr` `_esx_raw_lit_call` / `_esx_const_slot`.

## Reproduction

```cyr
fn f(): i64 {
    var r = 0;
#ifdef CYRIUS_ARCH_AARCH64
    const NR_UMOUNT2 = 39;
    r = syscall(NR_UMOUNT2, "/nonexistent", 0);
#endif
    if (r == 0 - 2) { return 0; }   # native umount2: -ENOENT
    return 1;                       # 39 ran getpid: a PID
}
syscall(60, f());
```

```sh
cat src/main_aarch64.cyr | build/cycc > cca && chmod +x cca
./cca < lc.cyr > lc.bin && chmod +x lc.bin && qemu-aarch64 ./lc.bin; echo $?
```

Actual: rc 0, **no warning**, exit 1 (39 ran getpid). The same call with the literal (`syscall(39, …)`, the `const`
line removed) warns: `raw syscall 39 inside a native-aarch64 region is renumbered → 172 (getpid); write 1039 for
native umount2`. A top-level `const NR_UMOUNT2 = 39;` or an `enum` constant declared in the region also warns (6.7.14,
`syscall constant NR_UMOUNT2 = 39, declared inside a native-aarch64 region, …`).

## Root cause

6.7.14 judges a folded constant by where it was DECLARED: enum constants and top-level consts record their name
token's expanded-source offset per var slot (`SVDECL`, src/common/util.cyr; called from PARSE_ENUM_DEF and
`_cst_record`), and `_esx_decl_in_region` asks whether that offset sits in a region opened in its own file. A fn-local
`const` is not a var slot: it lives in `_lc_tab` (src/frontend/parse_fn.cyr — name, scope depth, inline depth, kind,
value, float-literal index), which records no declaration token, so `_esx_const_slot` answers -1 for it (a name
`_lc_find` resolves is never judged).

## Proposed fix

Record the declaration offset in the `_lc_tab` entry (a seventh word) and judge it the way `_esx_decl_in_region`
judges a slot. ⚠ A local const inside an `#inline` fn is replayed at its call sites, so its declaration is in the
inline body's file, not the caller's — the offset must be the declaration's own token, never the replay site. Gate
row: tests/gates/platform/native_region_literal_warns.sh axis 7 (a fn-local const in a region warns; one declared
outside a region stays silent).
