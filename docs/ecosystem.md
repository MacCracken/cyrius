# Ecosystem

Downstream consumer repos that depend on the Cyrius toolchain.
**Refresh target**: every closeout pass (CLAUDE.md step 11),
plus whenever a port lands or a new repo joins.

## Status board

| Status | Repos |
|--------|-------|
| **Done** | agnostik, agnosys, argonaut, kybernet, nous, ark |
| **Done** | sakshi, majra, bsp, cyrius-doom, mabda, hadara |
| **Done** | sigil, patra, libro, shravan, tarang, yukti |
| **Done** | avatara, ai-hwaccel, hoosh, itihas, sankoch |
| **Done** | hisab |
| **In progress** | bhava |
| **In progress** | **bote** — MCP core service (JSON-RPC 2.0, tool registry, schema validation). Active port; unblocks vidya MCP. |
| **Blocked** | vidya MCP (needs bote) |

## Folded-in distlibs (sandhi-pattern)

Sibling repos vendored byte-identical into `cyrius/lib/` at a
patched tag. Removed from `[deps]` once folded. As of the mabda
3.0.1 fold (v6.0.45) there are no remaining explicit `[deps.*]`
git entries (see Live deps below).

| Lib | Folded at | Source tag | Domain |
|-----|-----------|------------|--------|
| `lib/sandhi.cyr` | v5.7.0 (refold v6.0.83) | sandhi 1.4.2 | HTTP/2 + JSON-RPC + service discovery + TLS policy (ALPN/SPKI on typed native verbs) |
| `lib/vani.cyr` | v5.8.0 (refold v5.8.65) | vani 0.9.3 | Audio (ALSA PCM + ring buffer + mixer) |
| `lib/sakshi.cyr` | v5.8.65 (refold v6.1.18) | sakshi 2.2.10 | Tracing |
| `lib/patra.cyr` | v5.8.65 | patra 1.10.3 | Storage |
| `lib/sigil.cyr` | v5.8.65 (refold v6.2.31) | sigil 3.9.2 | Security (x509 + Ed25519 sign/verify — powers native TLS + cyrsign release signing) |
| `lib/yukti.cyr` | v5.8.65 | yukti 2.2.3 | Hardware enumeration |
| `lib/sankoch.cyr` | v5.8.65 | sankoch 2.2.5 | Compression |
| `lib/niyama.cyr` | **v5.9.0** (2026-05-06) | niyama 1.0.2 | Regex (5 engines: bre / re2 / pcre / fuzzy / vim; 6,664 lines) |
| `lib/mabda.cyr` | **v6.0.45** (refold v6.2.30) | mabda 3.4.2 | GPU/compute (AMD-native GA; array textures + cubemaps + BC arrays + render-target VA fixes) |
| `lib/bayan.cyr` | **v6.1.25** | bayan 1.0.0 | Data formats + big-int (json / toml / cyml / csv / base64 / bigint `u256` / u128). **Carve** out of stdlib: public fns renamed `bayan_*` + legacy aliases. Consumers of `ws`/`sigil`/`patra`/`tls` (which call carved fns) must `include "lib/bayan.cyr"`. |
| `lib/ganita.cyr` | **v6.1.26** | ganita 1.0.0 | Linear algebra + advanced math (matrix / linalg / transcendental + fibonacci/binomial). **Carve** out of stdlib (closes Phase E): renamed `ganita_*` + legacy aliases. Keep stdlib `math` in scope (f64-exp/ln polyfills + F64 constants). |

## Live deps (explicit `[deps.*]`)

None. As of the mabda 3.0.1 fold (v6.0.45), `cyrius.cyml` has no
explicit `[deps.*]` git entries — every former dep is now a folded
distlib (see table above). `[deps].stdlib` is the auto-prepend list
only, not git resolution.

- **mabda** — folded byte-identical into `lib/mabda.cyr` (carved at 3.0.1
  / v6.0.45; **now 3.4.2 @ v6.2.30**) — removed from `[deps]`; opt-in via
  `include "lib/mabda.cyr"`.
- **agnosys** — was transitive via mabda's git resolution; with mabda
  vendored it is no longer pulled (re-add `[deps.agnosys]` if a
  consumer needs it).

## Downstream server-stack arc

10-layer hardened-server stack is consumer of the Cyrius
toolchain. Current status: **kavach is the last port blocking
completion** (memory: `project_server_stack.md`). Once kavach
lands, the server OS stack is feature-complete at the consumer
layer. No direct Cyrius-compiler release targets this — progress
is tracked in consumer repos. Listed here so it's not forgotten
across account switches.

## Deferred consumer projects

- **CYIM** — postponed until the server base OS is wrapped
  (memory: `project_cyim_deferred.md`). No Cyrius release target;
  resumes when the server-stack arc above closes.
- **sandhi repo extraction** — completed at v5.7.0 fold (see
  table above). Original "before v5.6.x closeout" target was
  revised to v5.7.0 clean-break per [sandhi ADR
  0002](https://github.com/MacCracken/sandhi/blob/main/docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md).

## Closeout audit checklist

Run during CLAUDE.md step 11 (vidya / docs sync) at every minor:

- [ ] Verify each **Done** repo still builds against the latest
      cyrius (their `cyrius.cyml` `cyrius` field points at the
      released tag — CLAUDE.md downstream-check, step 10).
- [ ] Move any **In progress** repo whose port landed to **Done**.
- [ ] Update fold-in lineage table when a new sibling distlib
      is vendored (e.g., niyama at v5.9.0).
- [ ] Refresh live-deps table when a `[deps.*]` entry bumps tag
      or the dep folds out of `[deps]`.
- [ ] Audit for symlink-corruption antipattern — see CLAUDE.md
      "Downstream repo setup (ecosystem rule)" for the
      `find` commands.
