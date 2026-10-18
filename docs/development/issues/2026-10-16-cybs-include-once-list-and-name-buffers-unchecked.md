# cybs's include-once list is unchecked: the 257th distinct include is skipped, and a 256+ character spelling is included twice — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-16 on the 6.7.14 infra lane's tree (l6714-infra @ 61e09667,
`bootstrap/cybs.cyr` seed-assembled, 23,010 B). Latent for the inputs that matter: `src/main.cyr`'s closure is 31
distinct includes, its longest spelling ~40 characters.
**Placement:** 6.7.15 — repair 5 (infra lane; filed from the 6.7.14 infra lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-16, the 6.7.14 infra lane (unit I4), while adding the refusals of
`issues/archived/2026-10-13-cybs-include-scratch-and-buffers-unchecked.md` (an include over its 2 MB slot, includes past 8
deep, stdin over 15 MB, an expansion over 16 MB — that item's filed surface). The include-once list and the include
name buffers are two more fixed preprocessor buffers that item does not list.
**Severity:** Low — a silent bad input to the trust root's bootstrap compiler, on the developer's own source, latent
(no shipped input is near either cap); a bug, not a vulnerability.
**Affects:** `bootstrap/cybs.cyr` `pp_seen` / `pp_mark` / `pp_do_include` (the layout predates 6.7.x).

## Reproduction

From the repository root:

```sh
cat bootstrap/cybs.cyr | bootstrap/asm > ./cybs && chmod +x ./cybs
# (1) 257 distinct includes: the 257th is skipped as if already included
i=1; while [ $i -le 255 ]; do printf '# f%s\n' $i > f$i.cyr; i=$((i+1)); done
printf '# x\n' > x.cyr; printf 'r = 42;\n' > y.cyr
{ printf 'var r = 0;\n'; i=1; while [ $i -le 255 ]; do printf 'include "f%s.cyr"\n' $i; i=$((i+1)); done
  printf 'include "x.cyr"\ninclude "y.cyr"\nsyscall(60, r);\n'; } > m.cyr
./cybs < m.cyr > m && chmod +x m && ./m; echo "257 includes: cybs run=$?"
build/cycc < m.cyr > mc; echo "257 includes: cycc rc=$?"
# (2) a 256+ character spelling: its entry runs into the next one, and a second include of it is not skipped
d=$(printf 'd%.0s' $(seq 1 100)); p="$d/$d/$d/l.cyr"; mkdir -p "$d/$d/$d"     # 308 characters
printf 'r = r + 1;\n' > "$p"; printf '# z\n' > z.cyr
printf 'var r = 40;\ninclude "%s"\ninclude "z.cyr"\ninclude "%s"\nsyscall(60, r);\n' "$p" "$p" > lp.cyr
./cybs < lp.cyr > lp && chmod +x lp && ./lp; echo "308-char spelling: cybs run=$?"
```

Output:

```
257 includes: cybs run=0
error: include-once table full (256 files) — split compilation unit
257 includes: cycc rc=1
308-char spelling: cybs run=42
```

Expected: (1) cybs refuses the 257th distinct include as cycc does (rc 1, nothing written) — it exits 0 having compiled
a program without `y.cyr` (`r` stays 0; the source says 42); (2) 41 — the second `include` of the same spelling is
skipped (cycc gets this wrong too for 128+ characters: `2026-10-16-include-once-path-of-128-chars-included-twice.md`).

## Root cause

- The once list is 256 entries × 256 B at `r15 + 0x7710000`, ending where the per-depth include name buffers begin
  (`r15 + 0x7720000 + depth * 4 KB`). `pp_mark` appends with no count check, so entry 256 IS depth 0's name buffer:
  the 257th include at depth 0 marks itself onto its own name, and the next include's name, written into that buffer,
  matches "entry 256" in `pp_seen` and is skipped.
- `pp_mark` copies the whole name, so a spelling of 256+ characters runs into the next entry, and the next `pp_mark`
  writes over its tail — the entry no longer equals the spelling, and a re-include is not skipped.
- `pp_do_include` copies the spelling into the 4 KB name buffer with no bound (until `"` or the file's end): a spelling
  over 4 KB runs into the deeper depths' buffers (unused while it is read, since 6.7.14 caps the depth at 8), and one
  over 96 KB (from depth 8; 128 KB from depth 0) into the `#ifdef` stack at `0x7740000`.

## Proposed fix

Refuse, naming the cap, through the shared refusal 6.7.14 added (`pp_cap_err` + a line of `err_cap`, no new label):
the 257th distinct include, a spelling of 256+ characters (the entry width; the name buffer's 4 KB is then never
reached). Seed labels are 508 / 512 after 6.7.14, and each check needs none. Rows in
`tests/gates/toolchain/cybs_diagnostics_named.sh` P: the two programs above refused with their caps' lines; 256
distinct includes and a 255-character spelling still compile. Seed-derive and the closure unchanged.
