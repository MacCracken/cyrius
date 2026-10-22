# Gates and check rows read other projects' checkouts — agnos, mirshi, sit, agnoshi, secureyeoman, every repo under `~/Repos` — a language does not gate on other projects — RESOLVED

> ✅ **RESOLVED in v6.7.16** (wave 0, on main, landed at the open before the lanes forked — f04b70121, 886fd2f60, c9462c7e7, ee353b12d, d67ca2896, 01e2c05a7, af750bb45, 1ce6ce850, 3ffd3a486, 918dff208, 7725b9e5d, 2e03629ec; the review's fixes e8eb181d5, a40fe0c2d, 611ceb6bd, fda4007a4, 27f326b28, 7b7ab9cbf, d3985f409; the user, 2026-10-19: "LANGUAGES DO NOT GATE ON OTHER PROJECTS"): no gate, check-driver row or release-gate step reads another project's checkout. The four agnos ABI / kernel parity gates leave whole; the mirshi runtime axes leave three gates (the static axes stay); the sit row, its lookup and check_sit_lookup_worktree.sh leave, and sankoch's DEFLATE / zlib is tested in-tree by tests/tcyr/formats/sankoch_deflate_roundtrip.tcyr (35 assertions, reference streams from the zlib C library); agnos-crossbuild-gate.sh part 2 (agnoshi) leaves, part 1 stays; the two secureyeoman TypeScript corpus rows leave (the user's decision: the in-tree corpus is its own arc after the 6.7.17 audit); removed_symbol_census.sh reads this checkout only and requires a docs/retired-symbols.allow row for every removed public name; two reads the table missed leave too (folds_agnos_parity.sh's sibling-manifest axis; distlib_named_deps_anchored.sh axis 4, now this tree's own plain `cyrius distlib` sidecar). `RG_SKIP_ALLOW` is empty, so the release gate passes no SKIP (release_gate_check_verdict.sh axes 10 and 12). The acceptance gate, tests/gates/toolchain/gates_read_only_the_tree.sh, refuses a `$HOME/Repos` read in any spelling, a `/home/<user>/` path, `CYRIUS_SIBLING_ROOT`, `<root>/..`, `dirname "<root>"`, a bare `../<name>` read and a driver literal beginning `../` in tests/gates, scripts and programs/checks — an allowlist of zero; axis 2 plants each shape RED, and a scratch tree at 99177e350 is RED on every read the table lists plus the two it missed. docs/development/dev-tools-linux.md lists every package the gates need, measured (gcc, clang, parted, mtools, edk2-ovmf, cpio, diffutils, git, tar and gzip added; Arch's `xxd` is `tinyxxd` or vim), and the network the "TLS live" row needs. check.sh at the open: 565 / 565, the driver 128 / 128, 0 SKIPs. ⚠ The acceptance's third item — `release-gate.sh` GREEN on a fresh machine with only the checkout and those packages — was not run in 6.7.16; the release gate ran on the development box. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — filed 2026-10-19 from the move of cyrius development to a new machine (`ans`): provisioning
it for a GREEN `release-gate.sh` required cloning and BUILDING four consumer projects, because the gates below read
their checkouts and SKIP without them — and `release-gate.sh` step 3 refuses every check.sh SKIP except
`RG_SKIP_ALLOW` (`agnos_monotonic_clock_rdtsc.sh`, `agnos_sysinfo_tail_parity.sh`). The user, 2026-10-19: "we need to
rip out all those gates longer term, LANGUAGES DO NOT GATE ON OTHER PROJECTS."
**Placement:** 6.7.16 — Break 2, repair 6 (wave 0 on main, landed at the 6.7.16 open, 2026-10-19, before the lanes fork) — never 7.x.
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
  edk2-ovmf, cpio and diffutils, and its Arch line names an `xxd` package Arch does not have — `xxd` comes from `vim`
  or `tinyxxd`; measured on ans 2026-10-19).
