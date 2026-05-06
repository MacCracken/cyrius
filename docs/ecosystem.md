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
patched tag. Removed from `[deps]` once folded; live deps below
remain explicit.

| Lib | Folded at | Source tag | Domain |
|-----|-----------|------------|--------|
| `lib/sandhi.cyr` | v5.7.0 | sandhi 1.x | HTTP/2 + JSON-RPC + service discovery + TLS policy |
| `lib/vani.cyr` | v5.8.0 (refold v5.8.65) | vani 0.9.2 | Audio (ALSA PCM + ring buffer + mixer) |
| `lib/sakshi.cyr` | v5.8.65 | sakshi 2.2.3 | Tracing |
| `lib/patra.cyr` | v5.8.65 | patra 1.9.3 | Storage |
| `lib/sigil.cyr` | v5.8.65 | sigil 3.0.1 | Security |
| `lib/yukti.cyr` | v5.8.65 | yukti 2.2.2 | Hardware enumeration |
| `lib/sankoch.cyr` | v5.8.65 | sankoch 2.2.4 | Compression |
| `lib/niyama.cyr` | **v5.9.0** (2026-05-06) | niyama 1.0.1 | Regex (5 engines: bre / re2 / pcre / fuzzy / vim; 6,664 lines) |

## Live deps (explicit `[deps.*]`)

| Dep | Version | Status |
|-----|---------|--------|
| **mabda** | 2.5.0 GA | Held pre-v3.0.0-rc.2 soak; Class B FFI/wgpu fncall6 ABI work pinned to v5.10.x. |
| **agnosys** | (transitive via mabda) | Held; folds out when mabda v3 lands. |

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
