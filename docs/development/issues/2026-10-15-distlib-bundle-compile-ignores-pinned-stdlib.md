# distlib: the bundle checks read `lib/<leaf>.cyr` from cycc's OWN version slot, not the manifest's pinned `versions/<pin>/lib` — the final "bundle compiles" check fails when only the pinned slot exists — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 stdlib lane's CLI and on the slot-open (7f57e532) CLI:
pre-existing, independent of the lane's ws fix.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane, wave 2, unit L4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — reached when the CLI runs with `CYRIUS_RESOLVED=1` (no re-exec into `versions/<pin>/bin/cyrius`)
and the manifest's `cyrius =` pin differs from the CLI's VERSION: the hermetic gates' setup, or a store missing the
pinned slot's binaries. It fails closed (rc 1) when the CLI's own slot is absent; when both slots exist, both checks
read the CLI's own slot — the bundle is verified against a stdlib that is not the one it pins (rc 0).
**Discovered:** 2026-10-15, the review of the 6.7.12 stdlib lane — the ws issue's repro
(`issues/archived/2026-10-13-ws-and-ws-server-declare-the-same-constants.md`) run truly verbatim (pin 6.7.11) on a 6.7.12 CLI
fails for this reason alone; `vec_new` fails the same way.

## Reproduction

```sh
F=/some/scratch; W=$F/distpin
mkdir -p $W/bin $W/home/versions/6.7.11
cp build/cyrius build/cycc $W/bin/                           # a 6.7.12 CLI + compiler
cat src/main_aarch64.cyr | build/cycc > $W/bin/cycc_aarch64; chmod +x $W/bin/cycc_aarch64
cp -R lib $W/home/versions/6.7.11/lib                        # the home holds ONLY the pinned slot
d=$W/p_vec; mkdir -p $d/src
printf '[package]\nname = "orp"\nversion = "0.1.0"\ncyrius = "6.7.11"\n\n[lib]\nmodules = ["src/lib.cyr"]\n' > $d/cyrius.cyml
printf 'fn orp_v(): i64 { var v = vec_new(); return v; }\n' > $d/src/lib.cyr
cd $d && CYRIUS_HOME=$W/home CYRIUS_RESOLVED=1 $W/bin/cyrius distlib; echo "rc=$?"
```

```text
  sidecar: 1 leaf(s), compile-verified (1 derived by the verify)
dist/orp.deps: 1 stdlib leaf requirements
  error: cannot open include file: lib/vec.cyr
error: distlib: the generated bundle does not compile: dist/orp.cyr
      (undefined fns are already downgraded — this is a REAL defect
       in the bundle, not the consumer's missing stdlib).
rc=1
```

The same with `return WS_OPEN;` (the ws issue's repro): `dist/orp.deps` = `ws`, then
`error: cannot open include file: lib/ws.cyr`, rc 1. Controls, same CLI:

- the home's slot and the pin both 6.7.12 → rc 0, `deps: vec`;
- pin 6.7.11 with BOTH `versions/6.7.11` and `versions/6.7.12` (identical copies) in the home → rc 0;
- the same, with a parse error appended to `versions/6.7.12/lib/vec.cyr` only (the pinned 6.7.11 slot intact) → rc 1,
  `error:lib/vec.cyr:380:12: expected identifier, got '{'` then `distlib: sidecar verify: the bundle with its leaves
  does not compile for x86_64-linux, and no symbol is missing — sidecar NOT written` (the intact file has 378 lines:
  the VERIFY read the CLI's slot, not the pin's).

The slot-open CLI (cbt/ at 7f57e532 built with its build/cycc, its own lib/ as the 6.7.11 slot) gives the identical
rc 1 "cannot open include file: lib/vec.cyr" — pre-existing.

## Root cause

The compiler's `lib/` include fallback (src/frontend/lex.cyr, `_init_cyrius_lib` / READFILE, 6.6.16): a
`lib/<leaf>.cyr` that does not open in the CWD is retried against ONE store slot, `CYRIUS_HOME/versions/<cycc's own
VERSION>/lib/` — never the manifest's `cyrius =` pin. distlib's sidecar verify mirrors the PINNED snapshot
(`_distlib_stdlib_root()` → `_distlib_mirror_make`, cbt/commands.cyr), but the measurements say the unit reaches that
mirror only when the cycc-version slot misses (only-6.7.11 home: verify OK; both slots: the verify read 6.7.12's
broken vec.cyr). The final self-check (`compile(dl_entry, dl_out)` with `_skip_deps = 0`, cbt/commands.cyr
~:6320-6412) has no mirror at all, so with only the pinned slot present its `lib/<leaf>.cyr` opens nowhere. Normally
the pinned re-exec (`_try_redirect_to_pinned`) hides this, because the re-exec'd CLI and its cycc ARE the pin's
version; with `CYRIUS_RESOLVED=1` (or a pinned slot without its `bin/`) the redirect is skipped and the checks read
the wrong stdlib or none.

## Fix direction (for whoever places it)

Have both distlib checks read `_distlib_stdlib_root()` (the pin) ahead of the compiler's own-version fallback — e.g.
compile the self-check entry from the mirror / with the pinned `lib/` in its CWD — so verify and final check read one
snapshot, the pinned one; rows in tests/gates/toolchain/ with the home holding only the pinned slot (rc 0), and with
both slots differing in one leaf (the checks read the pinned one).
