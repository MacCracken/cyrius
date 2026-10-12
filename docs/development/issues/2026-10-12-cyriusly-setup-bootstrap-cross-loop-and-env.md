# `cyriusly setup` (compiled): its "bootstrap cycc" step builds no cycc, its cross-bin loop can never match, and it builds the installed tools under an inherited `CYRIUS_BOUNDS` — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 on Linux x86_64 against the 6.7.10 slot-open tree (`efb6623f`,
`build/cycc` 2,057,744 B), with `cyriusly` built from `programs/cyriusly.cyr` by that `build/cycc`, run in a
`git archive HEAD` copy of the checkout with a throwaway `HOME` / `CYRIUS_HOME`. (a) With `build/cycc` removed,
`setup` prints "build/cycc not found — running bootstrap/bootstrap.sh...", which builds `build/cybs`, `build/asm` and
`build/cybs_check` only; the tool loop then fails 15 times (`./build/cycc: No such file or directory`), prints
`built 0 tool(s)`, leaves 15 zero-byte `build/<tool>` files, and `install.sh --refresh-only` stops with
`build/cycc missing — cannot rebuild cyrius …` (rc 1). (b) The cross loop strips a `cc5_` prefix; all four
`[release] cross_bins` (`cycc_aarch64`, `cycc_win`, `cycc-native-aarch64`, `cycc_cx`) map to a `src/main_cycc_….cyr`
that does not exist, so the loop never builds anything. (c) With `build/cycc` present and `CYRIUS_BOUNDS=1` in the
caller's environment, `setup` exits 0 and the installed `bin/cyrfmt` is byte-identical to a `CYRIUS_BOUNDS=1` build
(99,280 B) and differs from the default build (95,144 B).
**Placement:** 6.7.12 — repair 2, the CLI lane (roadmap.md § *6.7.12*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (its tools findings: `programs/cyriusly.cyr` `_cmd_setup`, read
against what `bootstrap/bootstrap.sh` builds); item (c) found by the 6.7.10 planning lane while reproducing it, which
re-verified and filed the whole.
**Severity:** Medium — (c) silently installs bounds-checked tools into the store from a shell that had the mode on
(the exact case 6.7.9 closed in the shell twin); (a) promises a bootstrap it cannot do and fails later, by another
name, with litter; (b) is dead code that would be wrong if "fixed" by its prefix alone.
**Affects:** the compiled `cyriusly` (`bin/cyriusly`, from `programs/cyriusly.cyr`) since its v5.11.10 port; (c)
since the bounds mode (6.7.8). The shell twin `scripts/cyriusly` has (a) only, and fails it by name.

## Summary

`_cmd_setup` is a native port of `scripts/cyriusly`'s `setup` arm that drifted from it:

- **(a) The bootstrap.** Both say they bootstrap cycc when `build/cycc` is missing, by running
  `sh bootstrap/bootstrap.sh`. That script assembles `cybs` from the seed and compiles `asm`; it never builds a cycc
  (`seed → cybs → cycc` is `scripts/seed-derive-cycc.sh`'s chain: cybs compiles `src/main.cyr` to gen1, gen1 compiles
  it to gen2 == `build/cycc`). The twin then checks `[ -x build/cycc ]` and stops with "bootstrap did not produce
  build/cycc"; the compiled one carries on, runs 15 compiles against a missing compiler (each `> build/$t` redirect
  creating an empty file) and fails inside `install.sh`.
- **(b) The cross loop.** `arch=${t#cc5_}` is from the `cc5_*` naming retired at v6.0.0. Today's names do not start
  with `cc5_`, so `src/main_$arch.cyr` is never found. Nothing is lost today only because `install.sh --refresh-only`
  rebuilds `cycc_aarch64`, `cycc_cx` and `cycc_win` itself (`scripts/install.sh:608-676`) and keeps the tracked
  `cycc-native-aarch64`. Correcting the prefix to `cycc_` would be WRONG: `cycc_win` needs `CYRIUS_TARGET_WIN=1` (it
  would build an ELF named `cycc_win`) and `cycc-native-aarch64` is built by `cycc_aarch64`, not `build/cycc`.
- **(c) The environment.** 6.7.9 added `unset CYRIUS_BOUNDS CYRIUS_POISON` to the twin's setup arm because the tools
  it builds are installed as they are (gate row E4, `tests/gates/frontend/bounds_mode_checked.sh`). The compiled
  setup builds the same tools through `exec_cmd` with the caller's environment and has no scrub; E4 scans
  `scripts/install.sh` and `scripts/cyriusly` only, so it does not see the compiled copy.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
W=$(mktemp -d); mkdir -p "$W/co" "$W/h" "$W/ch" "$W/h2" "$W/ch2"
git archive HEAD | tar -x -C "$W/co"                       # a clean checkout copy (build/cycc is tracked)
build/cycc < programs/cyriusly.cyr > "$W/cyriusly" 2>/dev/null && chmod +x "$W/cyriusly"
# (a) build/cycc missing: "bootstraps cycc" — bootstrap.sh builds cybs / asm only
( cd "$W/co" && rm build/cycc && HOME="$W/h" CYRIUS_HOME="$W/ch" "$W/cyriusly" setup </dev/null > "$W/a.log" 2>&1; echo "(a) rc=$?" )
grep -c 'build/cycc: No such file' "$W/a.log"; grep -E 'built|refusing|error:' "$W/a.log"
find "$W/co/build" -size 0 | wc -l                         # zero-byte tool files left behind
# (b) the cross loop strips `cc5_`: every cross_bins name maps to a src/main_<name>.cyr that does not exist
( cd "$W/co" && for t in cycc_aarch64 cycc_win cycc-native-aarch64 cycc_cx; do a=${t#cc5_}; [ -f src/main_$a.cyr ] || echo "(b) $t -> src/main_$a.cyr: absent, skipped"; done )
# (c) an inherited CYRIUS_BOUNDS=1 reaches the tools setup builds and installs
( cd "$W/co" && find build -size 0 -delete && cp /home/macro/Repos/cyrius/build/cycc build/cycc \
  && HOME="$W/h2" CYRIUS_HOME="$W/ch2" CYRIUS_BOUNDS=1 "$W/cyriusly" setup </dev/null > "$W/c.log" 2>&1; echo "(c) rc=$?" )
build/cycc < programs/cyrfmt.cyr > "$W/cyrfmt.plain" 2>/dev/null
CYRIUS_BOUNDS=1 build/cycc < programs/cyrfmt.cyr > "$W/cyrfmt.bounds" 2>/dev/null
cmp -s "$W/ch2/versions/$(cat VERSION)/bin/cyrfmt" "$W/cyrfmt.bounds" && echo "(c) installed cyrfmt == the CYRIUS_BOUNDS=1 build"
cmp -s "$W/ch2/versions/$(cat VERSION)/bin/cyrfmt" "$W/cyrfmt.plain" || echo "(c) installed cyrfmt != the default build"
cd /; rm -rf "$W"
```

```
actual:   (a) rc=1
          15
            built 0 tool(s)
            x build/cycc missing — cannot rebuild cyrius from cbt/cyrius.cyr; refusing to install a stale build/cyrius
          error: install.sh --refresh-only failed
          15
          (b) cycc_aarch64 -> src/main_cycc_aarch64.cyr: absent, skipped     (and the other three)
          (c) rc=0
          (c) installed cyrfmt == the CYRIUS_BOUNDS=1 build
          (c) installed cyrfmt != the default build
expected: (a) build/cycc derived from the seed (or refused by name before any tool build), no empty files;
          (b) no cross loop that cannot match; (c) the installed tools are the default build whatever the caller's
          environment holds
```

## Root cause

- `programs/cyriusly.cyr:799-808` (the header: "bootstraps cycc if missing") and `:823-832`: runs
  `sh bootstrap/bootstrap.sh` and never checks that `build/cycc` now exists.
- `programs/cyriusly.cyr:837` `build_cmd`: the tool loop (`cat … | ./build/cycc > build/$t`, which creates the empty
  file when the compiler is absent) and the cross loop's `arch=${t#cc5_}`.
- `programs/cyriusly.cyr:809-838`: no `CYRIUS_BOUNDS` / `CYRIUS_POISON` scrub before the builds; `_exec_shell`
  (`:582`) is `exec_cmd` with the inherited environment. The twin's scrub is `scripts/cyriusly:160`.
- `bootstrap/bootstrap.sh`: produces `build/cybs`, `build/asm`, `build/cybs_check` (its header says so).
- `scripts/cyriusly:166-175`: the twin's same bootstrap step, which at least refuses by name.

## Proposed fix

In `_cmd_setup` (and the twin's `setup` arm, so the two stay one behaviour):
1. When `build/cycc` is missing, derive it as `scripts/seed-derive-cycc.sh` does — `bootstrap.sh`, then
   `build/cybs < src/main.cyr > gen1`, `gen1 < src/main.cyr > build/cycc` — and check the result exists and is
   executable before any tool build; on any failure refuse by name and build nothing. (Or, if deriving is not wanted
   in `setup`, refuse by name pointing at the tracked `build/cycc` and `scripts/seed-derive-cycc.sh` — either holds;
   the header comment and the `setup` help row then say which.)
2. Delete the cross loop: `install.sh --refresh-only` already owns `cross_bins` and builds each one correctly.
3. Scrub `CYRIUS_BOUNDS` and `CYRIUS_POISON` for the builds (an envp without them for `exec_cmd`, or `env -u … ` in
   `build_cmd`), and extend gate row E4 to scan `programs/cyriusly.cyr`'s setup as well as the two shell files.
Rows (a `tests/gates/toolchain/` script, in a `git archive` copy with throwaway homes): `build/cycc` removed → setup
produces a `build/cycc` equal to the tracked one (or the named refusal), no zero-byte files; `CYRIUS_BOUNDS=1
cyriusly setup` installs a `cyrfmt` byte-identical to the default build. Mutation: drop the scrub → the
`CYRIUS_BOUNDS` row goes RED; drop the post-bootstrap check → the first row goes RED.

## Consumer-side workaround

Keep the tracked `build/cycc` (`git checkout build/cycc` restores it), and run `setup` from a shell with
`CYRIUS_BOUNDS` / `CYRIUS_POISON` unset (or run `sh scripts/install.sh --refresh-only` directly).
