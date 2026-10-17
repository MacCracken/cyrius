# cycc includes a file twice when its include path is 128 characters or longer — include-once stores 127 — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-16 on the 6.7.14 infra lane's tree (l6714-infra @ 61e09667, build/cycc =
gen2 of that src; the include-once code is unchanged since v4.8.4-alpha2).
**Placement:** 6.7.15 — repair 5 (infra lane; filed from the 6.7.14 infra lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-16, the 6.7.14 infra lane (unit I4), comparing cycc with cybs while probing cybs's include-once
list for the cybs preprocessor-buffers item (`issues/2026-10-13-cybs-include-scratch-and-buffers-unchecked.md`).
**Severity:** Low-Medium — a silent miscompile on the developer's own source: a second `include` of a file whose path
spelling is 128+ characters is not skipped, so its top-level statements run twice and its fns are defined twice (the
later definition binds, 6.6.20). No message. A bug, not a vulnerability.
**Affects:** `src/frontend/lex_pp.cyr` `PP_MARK_INCLUDED` / `PP_ALREADY_INCLUDED` (every cycc target; since v4.8.4-alpha2).

## Reproduction

```sh
q=$(printf 'q%.0s' $(seq 1 124)).cyr                      # a 128-character file name
printf 'r = r + 1;\n' > "$q"; printf '# z\n' > z.cyr
printf 'var r = 40;\ninclude "%s"\ninclude "z.cyr"\ninclude "%s"\nsyscall(60, r);\n' "$q" "$q" > lq.cyr
build/cycc < lq.cyr > lq && chmod +x lq && ./lq; echo "run=$?"    # 42: the file was included twice
q=$(printf 'q%.0s' $(seq 1 123)).cyr                      # 127 characters
printf 'r = r + 1;\n' > "$q"
printf 'var r = 40;\ninclude "%s"\ninclude "z.cyr"\ninclude "%s"\nsyscall(60, r);\n' "$q" "$q" > lq.cyr
build/cycc < lq.cyr > lq && chmod +x lq && ./lq; echo "run=$?"    # 41: once
```

Output:

```
run=42
run=41
```

Expected: 41 both times (the second `include` of the same spelling is skipped). A path reaches 128 characters easily
through directories (an absolute `~/.cyrius/deps/<name>/<version>/…` spelling, a deep source tree).

## Root cause

The include-once table is 256 entries × 128 B at `S + 0x1C0000`. `PP_MARK_INCLUDED` copies at most 127 bytes of the
name and NUL-terminates it there (`if (c >= 127) { break; }`); `PP_ALREADY_INCLUDED` compares the FULL name against the
entry and stops at the first difference, so a name of 128+ bytes differs from its own truncated entry at byte 127 and is
never "already included". The 256-entry count IS checked (`error: include-once table full (256 files)`); the entry
width is not.

Fix shape (the user's call where it changes what compiles): store the name in full (an alloc'd or wider table), or
compare at most the stored width — the latter would merge two distinct paths sharing a 127-byte prefix, so the former;
or refuse a name over the entry width by name. Row: the repro above gives 41 at 127, 128 and a 300-character spelling
through directories.

Related (cybs, the bootstrap compiler, same class, staged beside this):
`2026-10-16-cybs-include-once-list-and-name-buffers-unchecked.md`.
