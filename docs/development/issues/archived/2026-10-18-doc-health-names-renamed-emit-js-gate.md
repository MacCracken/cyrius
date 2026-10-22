# docs/doc-health.md still names the renamed gate toolchain/emit_js_refused_off_x86_linux.sh as a live pin — RESOLVED

> ✅ **RESOLVED in v6.7.16** (TL-1, `dfc4ca330` — no decision needed: a doc-currency ledger line. docs/doc-health.md's 6.6.6 bite-23 entry names `toolchain/emit_js_per_host_fork.sh` and says what that gate pins since 6.7.15's D38: `--target=js` runs on every POSIX host and is refused by name only on Windows, no longer refused off x86_64 Linux. The filed row, `grep -n emit_js_refused_off_x86_linux docs/doc-health.md`, prints nothing (rc 1; it printed line 304); nothing in scripts/, .github/, tests/ or programs/ reads the file. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 in the 6.7.15 platform lane's review (branch l6715-platform).
**Placement:** 6.7.16 — Break 2, repair 6 (tools lane, wave 1, unit T1; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — a doc-currency ledger cites a gate file that no longer exists; no script or workflow reads the
path (checked: `grep -rn emit_js_refused_off_x86_linux scripts .github tests programs` on the lane tree finds only
the history notes "was emit_js_refused_off_x86_linux.sh" in the new gate's header and its check-driver row).
**Found:** the lane's 19bf04a4c (--lex-ts / --parse-ts / --emit-js on every compiler, D38) deleted
tests/gates/toolchain/emit_js_refused_off_x86_linux.sh and replaced it with
tests/gates/toolchain/emit_js_per_host_fork.sh.

## Reproduction

```sh
grep -n emit_js_refused_off_x86_linux docs/doc-health.md
ls tests/gates/toolchain/emit_js_refused_off_x86_linux.sh tests/gates/toolchain/emit_js_per_host_fork.sh
```

```text
304:> `toolchain/emit_js_refused_off_x86_linux.sh`), so the doc and the behaviour move together.
ls: cannot access 'tests/gates/toolchain/emit_js_refused_off_x86_linux.sh': No such file or directory
tests/gates/toolchain/emit_js_per_host_fork.sh
```

(lines 302-304: "Both are now pinned by gates (`toolchain/self_host_src_per_target.sh`,
`toolchain/emit_js_refused_off_x86_linux.sh`), so the doc and the behaviour move together.")

## Root cause

The rename commit repointed the gates, check.sh and the guide but not the doc-health ledger entry (lines 302-304),
the only stale reference outside CHANGELOG history.

## Fix direction

Repoint docs/doc-health.md:302-304 to `toolchain/emit_js_per_host_fork.sh` (and re-word what it pins: since 6.7.15
--emit-js runs on every compiler, it is no longer refused off x86_64 Linux). Row: the grep above prints nothing.
