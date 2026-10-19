# Gates and check rows read other projects' checkouts — agnos, mirshi, sit, agnoshi, secureyeoman, every repo under `~/Repos` — a language does not gate on other projects — OPEN

**Status:** 🟡 **OPEN** — filed 2026-10-19 from the move of cyrius development to a new machine (`ans`): provisioning
it for a GREEN `release-gate.sh` required cloning and BUILDING four consumer projects, because the gates below read
their checkouts and SKIP without them — and `release-gate.sh` step 3 refuses every check.sh SKIP except
`RG_SKIP_ALLOW` (`agnos_monotonic_clock_rdtsc.sh`, `agnos_sysinfo_tail_parity.sh`). The user, 2026-10-19: "we need to
rip out all those gates longer term, LANGUAGES DO NOT GATE ON OTHER PROJECTS."
**Placement:** 6.7.16 — Break 2, repair 6 (the user, 2026-10-19; best landed FIRST, so 6.7.16's own gates — and a new
machine — need no consumer checkout) — never 7.x.
**Decision (user, 2026-10-19):** placed in 6.7.16; the TypeScript corpus replacement is its own arc after the 6.7.17
audit, so here the two secureyeoman rows leave the gate and the 40 in-tree fixtures are the measure until that arc.
**Severity:** Medium — the release gate's verdict depends on the state of consumer repos (their presence, their build,
their pins); a new machine cannot gate without them; and it inverts the top rule (CLAUDE.md: a consumer adapts to the
language, never the reverse; cyrius never surveys consumers).
**Kind:** process / gates (tests/gates, programs/checks, scripts) — no compiler change.

## What reads another project (measured 2026-10-19, `grep` of tests/gates, programs/checks, scripts)

| Reads | Where | What it checks today |
|---|---|---|
| `~/Repos/agnos/docs/development/agnos-userland-abi.md` | tests/gates/platform/agnos_abi_doc_parity.sh:28, agnos_net_config_field_parity.sh:23, agnos_sysinfo_tail_parity.sh:37 | cyrius's agnos-target syscall wrappers / record layouts against agnos's ABI document |
| `~/Repos/agnos/kernel/core/syscall.cyr` | tests/gates/platform/agnos_proclist_record_parity.sh:28 | the proc-list record against agnos's kernel source |
| `~/Repos/mirshi/build/mirshi` (a BUILT consumer binary, pinned to cyrius 6.6.2) | agnos_monotonic_clock_rdtsc.sh:239, agnos_sock_recv_bound.sh:115 (axis 5), agnos_sysinfo_tail_parity.sh:132 (runtime axis), io_rdwr_agnos.sh:76 | runtime axes: run cyrius-built agnos programs under mirshi |
| `~/Repos/sit/build/sit` (a BUILT consumer binary, pinned 6.6.2) | programs/checks/services.cyr `_sit_status_gate` (:1413, "sit fsck on 100-commit fixture reports 0 bad (pin v5.6.35; sankoch deflate)"), `_sit_find_dir` / `_sit_worktree_candidate`; tests/gates/toolchain/check_sit_lookup_worktree.sh (the lookup's own gate) | sankoch's deflate, exercised through sit |
| `../agnoshi` (`CYRIUS_AGNOSHI_DIR`) | scripts/agnos-crossbuild-gate.sh:448 (part 2, "the gating consumer") | cross-builds agnoshi's `agnsh` for `CYRIUS_TARGET_AGNOS` |
| `~/Repos/secureyeoman` (`SY_CORPUS`) | programs/checks/ts.cyr `_ts_corpus_gate` (:392), main.cyr:898 / :902 | "≥98 % of SY's 2,053 `.ts` / 435 `.tsx` parse" — the TypeScript front end's only broad measure: [its own issue](2026-10-19-typescript-support-measured-against-one-projects-files.md) |
| every repo under `~/Repos` (`CYRIUS_SIBLING_ROOT`, default the checkout's parent) | tests/gates/toolchain/removed_symbol_census.sh:33 | scans ~146 sibling repos (consumers) for uses of a removed stdlib symbol — a consumer survey inside a gate |

## Direction (each a bite; nothing here changes what a program compiles)

- **agnos ABI / kernel parity** (4 gates): remove. cyrius's agnos target is defined by cyrius's own `lib/` wrappers and
  their in-tree rows; keeping agnos's kernel in step with them is agnos's job, in agnos's CI. If the user wants a written
  contract, it is a document IN cyrius that agnos checks itself against — never the reverse.
- **mirshi runtime axes** (4 gates): remove the axes that need the binary; the static axes (the emitted code, the
  syscall numbers) stay. Then re-derive `RG_SKIP_ALLOW` (the two allowed SKIPs exist only because of these axes — after
  this, the release gate allows NO SKIP).
- **sit** (the driver row + check_sit_lookup_worktree.sh + `_sit_*`): remove; sankoch's deflate is tested directly
  (sankoch is a fold: its own suite, and an in-tree `lib/sankoch.cyr` row in cyrius if one is wanted — no consumer in
  between).
- **agnoshi** (agnos-crossbuild-gate.sh part 2): remove; part 1 (the in-tree `CYRIUS_TARGET_AGNOS` checks) stays.
- **secureyeoman**: the TS issue linked above replaces the measure; the two corpus rows leave the driver (a local,
  opt-in, non-gating smoke at most).
- **removed_symbol_census.sh**: scope it to cyrius itself and the 12 folded stdlibs (sandhi, vani, sakshi, patra, sigil,
  yukti, sankoch, niyama, mabda, bayan, ganita, yantra — `docs/ecosystem.md`), or to `docs/retired-symbols.allow` alone;
  never the consumer repos.

## Acceptance

- No gate, check-driver row or `release-gate.sh` step reads a path outside the cyrius checkout, its `build/`, its
  throwaway `CYRIUS_HOME` and `TMPDIR` — a new gate refuses `$HOME/Repos/`, `../<name>` and `CYRIUS_SIBLING_ROOT` reads in
  tests/gates, scripts and programs/checks (an allowlist of zero), with a mutation (a planted `~/Repos/x` read → RED).
- `RG_SKIP_ALLOW` re-derived (empty if the two agnos SKIPs were only the mirshi axes).
- A fresh machine with only the cyrius checkout and the packages in `docs/development/dev-tools-linux.md` runs
  `release-gate.sh` GREEN; that document lists every package the gates need (today it omits gcc, clang, parted, mtools,
  edk2-ovmf, cpio and diffutils).
