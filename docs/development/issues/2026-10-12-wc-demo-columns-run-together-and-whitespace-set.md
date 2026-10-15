# `programs/wc.cyr` (a demo): counts of 8 or more digits run together with no separator, and VT / FF do not separate words — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 on Linux x86_64 against the 6.7.10 slot-open tree (`efb6623f`,
`build/cycc` 2,057,744 B), `programs/wc.cyr` built by that `build/cycc`, compared with GNU coreutils `wc` 9.12 under
`LC_ALL=C`. A 10,000,000-byte one-word input prints `       0       110000000` (the word count `1` and the byte count
`10000000` fused into `110000000`); GNU prints `       0        1 10000000`. `a\vb\fc\n` counts 1 word; GNU counts 3.
**Placement:** 6.7.12 — repair 2: the platform release (tools lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (its tools findings: `programs/wc.cyr`); re-verified and filed by the
6.7.10 planning lane.
**Severity:** Low — a demo program; its output is unreadable for any count of 8+ digits and its word count disagrees
with the tool it imitates on two whitespace bytes. No gate or doc depends on it.
**Affects:** `programs/wc.cyr` as long as it has had `print_num`.

## Summary

`print_num` right-justifies each count in an 8-column field and writes no separator, so the fields only stay apart
while every count has at most 7 digits; an 8-digit count fills its field and touches the one before it. `is_ws`
accepts space, tab, LF and CR only; the C `isspace` set GNU `wc` uses in the C locale also includes vertical tab (11)
and form feed (12).

## Reproduction

```sh
cd /home/macro/Repos/cyrius
W=$(mktemp -d)
build/cycc < programs/wc.cyr > "$W/wc" 2>/dev/null && chmod +x "$W/wc"
head -c 10000000 /dev/zero | tr '\0' a > "$W/big"            # 10,000,000 bytes, one word, no newline
"$W/wc" < "$W/big"; LC_ALL=C wc < "$W/big"
printf 'a\vb\fc\n' > "$W/vf"                                  # VT and FF between words
"$W/wc" < "$W/vf"; LC_ALL=C wc < "$W/vf"
rm -rf "$W"
```

```
actual:          0       110000000
                 0        1 10000000        (GNU)
                 1       1       6
          1 3 6                              (GNU)
expected: the three counts separated however wide they are; 3 words for a\vb\fc
```

## Root cause

- `programs/wc.cyr:9-25` `print_num`: pads to 8 columns (`while (23 - i < 8)`) and never emits a separator.
- `programs/wc.cyr:4-7` `is_ws`: `32 || 9 || 10 || 13` — no 11 (VT) or 12 (FF).

## Proposed fix

Write one space before each count (or pad to a width that leaves at least one blank, GNU-style: right-justified to
the widest count, single-space separated), and make `is_ws` the C `isspace` set (9–13 and 32). A row in whatever
gate runs the demos (or a small `tests/tcyr/` case compiling the logic): a 10,000,000-byte input whose three fields
parse back as `0 1 10000000`, and `a\vb\fc\n` → 3 words. Mutation: drop the separator → the first row goes RED.
(GNU `wc` 9.12 also splits `a<U+00A0>b` into 2 words; a byte-level demo matching that is not proposed.)

## Consumer-side workaround

Use the system `wc`; the demo is not a tool.
