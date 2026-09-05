# Proposal — `cyrius.cyml` as the build tool's actual configuration, not a partly-read file

**Filed:** 2026-09-04 · **Status:** 🟡 OPEN — for maintainer direction

> ### ⛔ Update v6.5.51 — the v6.5.49 slice shipped INERT, and the reason belongs in this proposal
>
> The `[build]` path fallback read **`src`**, which is the key *this* repo's manifest happens to
> use. Counted across `~/Repos` on 2026-09-04: **120 of 125 `cyrius.cyml` files declare `entry`,
> and 5 declare `src`** — one of the five being cyrius itself. A pre-v6.5.51 CLI handed an
> `entry=` manifest printed the usage text and exited 1, i.e. presented as *"this feature does
> not exist"* to 96 % of the ecosystem. Fixed at v6.5.51: both keys, `entry` first.
>
> ⚠ **Its gate passed the whole time, because the gate's fixture manifest was written with the
> same key the implementation read.** That is the failure mode this proposal should design
> against, not just the missing key: a gate authored alongside an implementation encodes the
> implementation's assumptions and confirms that the code does what the code does.
>
> **This sharpens the proposal's central point.** The table below classifies keys as live or
> inert. `src`/`output` were *neither*: they were live in the code and inert in practice,
> because the code and the ecosystem disagreed about the spelling. Any "make the manifest
> authoritative" design therefore needs a **declared key vocabulary with synonyms resolved in
> one place**, plus a check that the vocabulary matches what consumers actually write — a
> hand-maintained duplicate of a derivable fact is the self-drifting shape this cycle keeps
> finding.
**Prompted by:** `cyrius build` requiring `<source> <output>` on every invocation while the
manifest already declared both. One slice of this shipped at **v6.5.49** (the `[build]` path
fallback); this proposal is the rest, and the shape it should take.

## The pattern worth naming

`cyrius.cyml` is read **partially and inconsistently**. Some keys are load-bearing, some are
decorative, and nothing distinguishes them:

| Key | Read by | Status before 6.5.49 |
|---|---|---|
| `[package].cyrius` | the wrapper's pin redirect | live |
| `[release].bins` / `.scripts` | `release.yml` (awk), `install.sh`, `pulsar` | live |
| `[deps].stdlib` | `cyrius deps`, auto-prepend | live |
| `[build].modules` | `cbt/deps.cyr` | live |
| **`[build].src` / `.output`** | **nothing** | **inert** |

⛔ **An inert key cannot be observed to be wrong.** The cyrius repo's own manifest declared
`output = "build/cc5"` — the *prior-major* compiler, tracked as a break-glass reference — and
nobody noticed, because nothing ever used it. Implementing the fallback is exactly what would
have made that value destructive. That is the general hazard: **a manifest key that is documented
but unread is a loaded gun with the safety on**, and every feature that starts reading one is a
chance to fire it.

## What shipped at v6.5.49

The override ladder, gated by `tests/gates/toolchain/build_reads_manifest_paths.sh`:

```
cyrius build                 -> [build] src + [build] output
cyrius build <src>           -> that src    + [build] output
cyrius build <src> <out>     -> both explicit; the manifest is NOT consulted
```

Command-line arguments win outright. The manifest is consulted **only** for arguments not given —
reading it otherwise would let a stale key override an explicit flag.

## What this proposal asks for

Three things, in priority order. Each is independently shippable; **none should ship without the
audit in (0)**.

### 0. Prerequisite — audit every manifest key for read/unread status

Before adding readers, enumerate which keys are live and which are decorative, and either wire or
delete the decorative ones. The `build/cc5` case says an unread key drifts silently; adding more
readers without this just widens the blast radius. **A gate should assert the inventory**, in the
same shape as the agnos-parity family: for each documented key, is anything reading it?

### 1. `[build]` should carry the flags that are currently retyped every time

`target` / `arch`, `strict`, `features`, `defines`. Today these are command-line only, so a
project with a fixed target repeats it on every invocation and in every CI line — the same
duplication the path keys just removed.

⚠ **The precedence rule must be the one 6.5.49 established and must not vary per key**: explicit
argument > manifest > built-in default. A per-key exception is how a configuration system becomes
unpredictable.

### 2. `cyrius build --print-config`

Resolve the full configuration and print it with each value's **origin** (`argument`, `manifest`,
`default`). Cheap to implement, and it is the thing that makes a precedence ladder debuggable
rather than mysterious. It is also the natural regression surface: a gate can assert origins
directly instead of inferring them from side effects, which is what axis 3 has to do today.

### 3. Named build profiles — `[build.debug]`, `[build.release]`

⚠ **This one is a genuine design decision and is deliberately last.** It introduces a selector
(`cyrius build --profile release`), inheritance rules, and a default-profile question. sigil
already carries thirteen `distlib` profiles with their own selector; a second, differently-shaped
profile concept in the same file would be worse than none. **Do not start this without deciding
whether it shares sigil's model.**

## Explicitly out of scope

- **A general `[env]` or script-hook section.** That is a build system, and it invites shelling
  out — against the sovereignty rule that keeps bash out of shipped deliverables.
- **Auto-discovering `src/main.cyr` with no manifest key.** Convenient and wrong: it would make
  the build silently target a different file when a project restructures. The key is the contract.

## Open question for the maintainer

Should `[build].output` be treated as a **default** or as an **assertion**? Today it is a default.
As an assertion, `cyrius build` writing anywhere else would warn — which would have caught the
`build/cc5` drift the day it was written, at the cost of noise in repos that legitimately build
several outputs from one manifest.
