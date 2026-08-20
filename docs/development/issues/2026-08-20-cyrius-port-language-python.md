# `cyrius port --language=python` — declined, but the first-party standard mandates using the tool

**Status:** 🟡 **OPEN** — a real Python→Cyrius port is underway and has no supported scaffolding path.
**Placement:** unpinned — 6.5.x backlog. `programs/cyrius-init.cyr` (`cmd_port`).
**Discovered:** 2026-08-20 while starting the **agnostic** Python→Cyrius port.
**Severity:** Low — `cyrius init --language=none .` is a working substitute; the gap is that the
documented porting path does not cover a language a first-party port is actually being done in.
**Affects:** cyrius CLI 6.5.31 (the decline has been in place since the `--language` flag was added).

## Summary

`cyrius port` accepts `--language=<lang>` and its usage text advertises `rust (future: go, python, …)`.
Passing `python` is explicitly declined:

```
$ cyrius port --language=python /path/to/project
error: --language=python not yet supported (planned for future v5.6.x)
  currently supported: rust
```

`programs/cyrius-init.cyr:986-989` — the decline branch, shared with `go`, `c`, `cpp`, `zig`, `ocaml`
and `haskell`.

Two things make this worth filing rather than silently working around:

1. **The stated milestone has long passed.** The message says *"planned for future v5.6.x"*; the
   toolchain is at **6.5.31**, roughly a full major line later.
2. **The first-party standard mandates the tool.**
   `agnosticos/docs/development/first-party/first-party-standards.md:24` —
   *"**Always use Cyrius tooling to scaffold and port.** Do not manually create project structures.
   The tools ensure consistency across 130+ repos. If the tools are missing something, fix the tools
   — don't work around them."*
   A consumer doing a Python port is therefore told to use a tool that declines the job.

## Reproduction

```sh
$ cyrius --version
cyrius 6.5.31

$ cyrius port --language=python /home/macro/Repos/agnostic
error: --language=python not yet supported (planned for future v5.6.x)
  currently supported: rust
```

Usage text for contrast (`programs/cyrius-init.cyr:882`):

```
  --language=<x>  source language being ported FROM (default: rust)
                  supported: rust  (future: go, python, …)
```

## What the rust path does, for sizing

From `cmd_port` (`programs/cyrius-init.cyr:957-1024`), the rust flow is:

1. require `--language=rust` (`:980`)
2. precondition: `Cargo.toml` exists in the target (`:999`)
3. precondition: `rust-old/` does not already exist (`:1002`)
4. count Rust LOC for the port record
5. `sys_mkdir` `rust-old/` and move the Rust tree into it (`:1021-1024`)
6. scaffold the Cyrius project structure over the top

Only steps 1–5 are language-specific, and only in three details: the flag value, the marker file, and
the destination directory name. A Python arm would be:

| | rust | python |
|---|---|---|
| marker file | `Cargo.toml` | `pyproject.toml` (fall back to `setup.py` / `setup.cfg`) |
| destination | `rust-old/` | `python-old/` |
| LOC count | `*.rs` | `*.py` |
| port-comparison doc | `docs/benchmarks-rust-v-cyrius.md` | `docs/benchmarks-python-v-cyrius.md` |

The layout section of the standard (`first-party-standards.md:96`) names `rust-old/` explicitly, and
the documentation standard's retirement-via-git-tag pattern is language-agnostic, so a `<lang>-old/`
generalisation appears consistent with both.

## Proposed fix

Generalise the language arm rather than adding a second copy of it: a small table of
`{flag, marker_file, old_dir, source_ext}` keyed by language, with `rust` as the default entry, so
`go`/`c`/`cpp`/`zig` become table rows rather than new branches. Whatever the shape, the usage text
and the decline message should agree with what is actually supported, and the stale
*"planned for future v5.6.x"* string should go.

Filing only — per this consumer's operating rule the cyrius tree is not modified from a consumer repo.

## Consumer-side workaround

`cyrius init --language=none .` scaffolds in place over an existing directory (skip-existing), which
is the documented greenfield mode (`programs/cyrius-init.cyr:609-610`). For **agnostic** the Python
tree had already been moved aside to `python-port/` by hand before this was discovered, so the only
part `cyrius port` would have contributed — the move — was already done. The scaffold is therefore
tool-generated even though the port step was not.

Note the directory name differs from the convention this issue proposes (`python-port/` rather than
`python-old/`); that repo is keeping its existing name, so a future `--language=python` should not
assume it can create `python-old/` unconditionally in an already-ported tree.

---

## Related, found in the same session: `cyrius init` creates fewer files than the standard says

`first-party-standards.md:36` describes the scaffolder as producing:

> `cyrius init` creates: `cyrius.cyml`, `src/main.cyr`, `src/test.cyr`, `lib/` (vendored stdlib),
> `scripts/`, `docs/`, CI workflows, VERSION, LICENSE, README, CHANGELOG, .gitignore.

and the lifecycle block at `first-party-standards.md:789-792` extends that list to
`CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, CLAUDE.md, .gitignore, Makefile, scripts/`.

Measured on a real in-place run at 6.5.31 (`cyrius init --language=none .` in an empty repo):

| file | standard says | 6.5.31 creates |
|---|---|---|
| `cyrius.cyml`, `src/{main,test}.cyr`, `lib/`, VERSION, LICENSE, README, CHANGELOG, `.gitignore` | yes | ✅ |
| `CLAUDE.md` | yes | ✅ |
| `.github/workflows/{ci,release}.yml` | yes | ✅ |
| `docs/` tree (adr, architecture, development, guides, examples) | yes | ✅ |
| `tests/*.{tcyr,bcyr,fcyr}` | — | ✅ (bonus) |
| **`CONTRIBUTING.md`** | yes | ❌ |
| **`CODE_OF_CONDUCT.md`** | yes | ❌ |
| **`SECURITY.md`** | yes | ❌ |
| **`scripts/`** (incl. `version-bump.sh`, which the standard lists under Required layout) | yes | ❌ |
| **`Makefile`** | yes (optional per the layout section) | ❌ |
| `docs/architecture/overview.md` | named by the lifecycle step 8 | ❌ (creates `docs/architecture/README.md`) |

Every one of those is listed under **Required layout** at `first-party-standards.md:84-134`, so a repo
scaffolded strictly by the tool is not conformant on the day it is created, and each consumer
hand-writes the same four files. Either the tool should emit them or the standard should stop
promising it does — the two currently disagree.

No workaround needed beyond copying the files from a conforming sibling (agnosai, majra, patra all
carry them), which is what this port did.

### And the scaffold's own source trips the flat-namespace discipline

`cyrius init` writes this as the generated entry point:

```cyrius
var r = main();
sys_exit_group(r);
```

`r` is a **bare top-level `var` in Cyrius's single flat symbol table**. The ecosystem treats that as a
hazard serious enough to gate in CI — agnosai's `src/main.cyr` carries a comment explaining why its
equivalent is named `_agnosai_exit_code`:

> Prefixed like everything else: this is a top-level `var` in Cyrius's single flat namespace, so a
> bare `r` here is a global that could shadow — or be shadowed by — any dep that happens to use the
> same name.

and `scripts/check-symbols.sh` exists precisely to catch it, after a 2026-07-31 audit found four
duplicated enum constants, three with different values, three of them struct sizes passed straight to
`alloc()`. Running that gate against a freshly-initialised repo fails immediately on the scaffolder's
own output.

Separately, `init` emits `main` and `r` into **both** `src/main.cyr` and `src/test.cyr`. Those are
distinct translation units (`[build].test` compiles alone), so it is not a real collision — but any
whole-`src/` symbol scan reports it as one, which is a false positive every consumer adopting the
gate has to special-case.

Suggested: name the generated global `_{project}_exit_code`, matching what every conforming repo in
the ecosystem already does.
