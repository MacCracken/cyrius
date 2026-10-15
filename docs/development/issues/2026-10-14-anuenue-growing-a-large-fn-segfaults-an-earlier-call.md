# Appending code to the end of a large function makes an EARLIER call in it segfault — OPEN

**Status:** 🟡 **OPEN** — filed by a consumer; reproduced 2026-10-14 on Linux x86_64 under three toolchains.
Not minimized and not investigated: the consumer only surfaces it.
**Placement:** unplaced — for the user to place.
**Source:** anuenue (`/home/macro/Repos/anuenue`), found while cutting its 1.4.3 (the escape-table word copy).
**Discovered:** 2026-10-14, adding one unit-test group to `tests/anuenue.tcyr`.
**Severity:** Medium — a hard crash with a known workaround. It may be worse than it looks: the failure is
far from the code that triggers it, so a variant that corrupts instead of crashing would be silent.
**Affects:** cycc 6.7.9 (`8bb8df56`), 6.7.10 (`7c97af24`), and a local 6.7.11 build (`42f5a974`, dirty,
untagged). Earlier releases were not checked.

## Summary

`tests/anuenue.tcyr`'s `fn main()` is one long function holding every unit-test group anuenue has written
since its first milestone, about 140 locals. Appending one more group, about 50 lines just before its final
`return assert_summary();`, makes the suite die with SIGSEGV in its **third** group. That group is a
`cmdit_new` + `cmdit_parse_argv` call, which runs long before the appended lines are reached.

The same 50 lines moved into a function of their own, called from the same spot, pass. That is the shipped
workaround, below. Without the appended lines, the suite passes 429/429.

## Reproduction

The downstream tree, pinned: anuenue tag `1.4.2`, commit `2fece2d`.

```sh
git clone https://github.com/MacCracken/anuenue.git && cd anuenue
git checkout 1.4.2                    # 2fece2d
# Paste the block below into fn main() of tests/anuenue.tcyr, on the line immediately
# before main()'s final `return assert_summary();`.
cyrius deps
cyrius test
```

The block (anuenue 1.4.3's `test_word_copy` body; every name it uses exists at 1.4.2):

```cyrius
    test_group("v1.4.3 — the escape word copy: footprint, scratch, geometry");
    # _emit_phase_esc writes [pos, pos + 24) whatever elen is, so every
    # caller needs 24 bytes of room — the reserve they already keep.
    assert_eq(ANUENUE_ESC_TABLE_ENTRY_SIZE - 8 <= ANUENUE_FLUSH_RESERVE, 1,
      "the 24-byte write footprint fits FLUSH_RESERVE");
    # The scratch past elen must be zero even after a rebuild IN PLACE from
    # a longer mode: truecolor (up to 17 bytes) then 16-colour (5). Without
    # init's zero-fill, bytes 5..16 of each entry would still hold the
    # truecolor escape.
    ANUENUE_COLOR_MODE = ANUENUE_COLOR_TRUE;
    _phase_esc_init();
    ANUENUE_COLOR_MODE = ANUENUE_COLOR_16;
    assert_eq(_phase_esc_init(), 0, "rebuild in place for 16-colour");
    var wc_dirty = 0;
    var wc_i = 0;
    while (wc_i < ANUENUE_PHASE_MOD) {
        var wc_entry = _PHASE_ESC_TABLE + wc_i * ANUENUE_ESC_TABLE_ENTRY_SIZE;
        var wc_k = load64(wc_entry);
        while (wc_k < 24) {
            if (load8(wc_entry + 8 + wc_k) != 0) { wc_dirty = wc_dirty + 1; }
            wc_k = wc_k + 1;
        }
        wc_i = wc_i + 1;
    }
    assert_eq(wc_dirty, 0, "every entry's payload past elen is zero after the rebuild");
    # The footprint at an unaligned pos: escape, zero scratch to pos + 24,
    # untouched after.
    var wc_buf[40];
    var wc_j = 0;
    while (wc_j < 40) { store8(&wc_buf + wc_j, 0xAA); wc_j = wc_j + 1; }
    var wc_end = _emit_phase_esc(&wc_buf, 3, 100);
    assert_eq(wc_end, 3 + 5, "16-colour: pos advances by elen (5), not 24");
    assert_eq(load8(&wc_buf + 3), 27, "the escape starts with ESC at pos");
    assert_eq(load8(&wc_buf + 2), 0xAA, "the byte before pos is untouched");
    var wc_zero = 1;
    wc_j = wc_end;
    while (wc_j < 3 + 24) {
        if (load8(&wc_buf + wc_j) != 0) { wc_zero = 0; }
        wc_j = wc_j + 1;
    }
    assert_eq(wc_zero, 1, "pos + elen .. pos + 24 is zero scratch");
    var wc_after = 1;
    wc_j = 3 + 24;
    while (wc_j < 40) {
        if (load8(&wc_buf + wc_j) != 0xAA) { wc_after = 0; }
        wc_j = wc_j + 1;
    }
    assert_eq(wc_after, 1, "nothing from pos + 24 on is touched");
    ANUENUE_COLOR_MODE = ANUENUE_COLOR_TRUE;
    _phase_esc_init();
```

**Actual** (all three toolchains):

```
=== M2 flags — --help short-circuits to CMDIT_HELP ===
=== M2 flags — short -V short-circuits to CMDIT_VERSION ===
  FAIL: tests/anuenue.tcyr (killed by signal 11 SIGSEGV — the test never reached a verdict)
```

**Expected:** the suite runs to a verdict. At 1.4.2 a few of the block's own assertions fail, because 1.4.2
predates the code they test. A test failure, not a crash.

**Control:** the unmodified 1.4.2 tree passes, `429 passed, 0 failed`.

## What the consumer ruled out

Each probe was added at the same spot in a passing tree, instead of the block:

| Added to `main()` | Result |
|---|---|
| twelve `var x = N;` integer locals | passes |
| `var a[40];` plus a `store8` into it (also tried 8 / 16 / 24 / 32 bytes) | passes |
| forty trivial statements (`if (load8(&buf + k) == 255) { flag = 1; }`) | passes |
| the block truncated before its last two read-only `while` loops | passes |
| the full block | **SIGSEGV in group 3** |

So it is not the local count, an array local, or the amount of code on its own. Untested: the number of
string literals in the function (the block adds about ten), and stack-frame layout as a whole.

## Root cause (if known)

Not known; not investigated by the consumer. Speculation, flagged as such: something that scales with the
function as a whole, and is not the local count, misplaces a value that an early call depends on.

## Proposed fix

None — just surfacing.

## Consumer-side workaround (if any)

Keep functions small. anuenue 1.4.3 (`7750cc6`) puts the new group in its own function, `fn test_word_copy(): i64`, called
from `main()`. Its CLAUDE.md now records large functions as a miscompile risk, and its 1.4.4 closeout splits
`main()` into one function per milestone or cut.
