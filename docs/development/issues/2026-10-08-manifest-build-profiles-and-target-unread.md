# `cyrius.cyml` has no named build profiles (`[build.PROFILE]`), and `[build] target` is held — warned, never read — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-08 against 6.7.6 @ 2fb6ad8b (CLI built from `cbt/cyrius.cyr` by the tree's
`build/cycc`, throwaway `HOME` / `CYRIUS_HOME`): a manifest with `[build] target = "aarch64"` and `[build.release]
defines = ["REL"]` builds an x86_64 ELF with `REL` undefined and warns twice; `cyrius build --profile release` is
`unknown option '--profile'`.
**Placement:** open by design — a feature / arc, not a bug: roadmap-future.md § *DX / toolchain* (placed 2026-10-09) — never 7.x.
**Discovered:** the 6.6.17 manifest arc (proposal `proposals/archived/2026-09-04-build-tool-manifest-integration.md`
§3, "P1's deferred half"; CHANGELOG [6.6.17] m4); filed 2026-10-08 from roadmap.md.
**Severity:** Low — a configuration gap, warned by name; every value has a command-line spelling.
**Affects:** the `cyrius` CLI 6.6.17 – 6.7.6.

## Summary

6.6.17 made `cyrius.cyml` the build's configuration — one key vocabulary (`cbt/manifest.cyr` `_mf_vocab_a` /
`_mf_vocab_b`), one precedence rule (argument > environment > manifest > default), `--print-config` — and left two
things out on purpose:

1. **Named profiles.** `[build.debug]` / `[build.release]` are not a known section (`warn: cyrius.cyml [build.release]
   is not a known section and nothing reads it`) and there is no selector. The proposal deferred them as "a genuine
   design decision": a selector (`--profile <name>`), inheritance from `[build]`, a default profile, and whether it
   shares the model of the `[lib.PROFILE]` distlib profiles (`cyrius distlib <profile>`) a fold like sigil already
   uses thirteen of.
2. **`[build] target`** is vocabulary row 15, state `held` (`cbt/manifest.cyr:41`): `warn: cyrius.cyml [build] target
   is HELD and not read: pass --target / --aarch64 / --win / --agnos on the command line`. A project with a fixed
   target retypes it on every invocation and CI line — the duplication the proposal's §1 set out to remove.

## Reproduction

```sh
mkdir -p p/src && cd p
printf 'fn main(): i64 {\n    #ifdef REL\n    return 3;\n    #endif\n    return 0;\n}\nvar r = main();\nsyscall(60, r);\n' > src/main.cyr
cat > cyrius.cyml <<'EOF'
[package]
name = "pprof"
version = "0.1.0"

[build]
entry = "src/main.cyr"
output = "build/pprof"
target = "aarch64"

[build.release]
defines = ["REL"]
EOF
cyrius build                    # both warnings; "compile src/main.cyr -> build/pprof [x86_64] … OK"
file build/pprof                # ELF 64-bit LSB executable, x86-64
./build/pprof; echo $?          # 0  (REL never defined)
cyrius build --profile release  # error: cyrius build: unknown option '--profile'
```

## Root cause

By design at 6.6.17: `target` is declared `held` in the vocabulary (`cbt/manifest.cyr:41`) and
`_cfg_resolve_build` resolves no `target` rung; `build.*` is not a section in the vocabulary.

## Proposed fix

Both change what an existing manifest builds, so the shape is the USER's decision before any code:
- `[build] target`: read it as the manifest rung of the existing `--target` / `--aarch64` / `--win` / `--agnos`
  precedence (argument still wins). A manifest that declares it today, warned and ignored, would start producing that
  target's binary.
- Profiles: pick the selector, the inheritance rule (a profile overrides `[build]` key by key?), the default (none =
  `[build]` alone?), and whether `[build.X]` and `[lib.X]` share one profile namespace and selector. Then add the
  section to the vocabulary, resolve it in `_cfg_resolve_build`, and show its origin in `--print-config`.
