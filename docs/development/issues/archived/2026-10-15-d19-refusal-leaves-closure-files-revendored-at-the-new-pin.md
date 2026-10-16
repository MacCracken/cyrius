# After D19's pin-move refusal, the closure files are already re-vendored at the new pin, so `deps --verify` fails on them while the refusal says only that the lock is unchanged — RESOLVED

> ✅ **RESOLVED in v6.7.13** (TL-12, under the user's decision D41, 2026-10-15: (a) refuse before anything is written. At a pin move where some lib/ file differs from the new snapshot, `cyrius deps` and `cyrius build` first run the resolve once into a private scratch, with stdout and stderr muted, to learn the closure (`_deps_pin_move_dry`). `_cbt_mute` is a dup2 of /dev/null on POSIX and SetStdHandle to NUL on Windows. They then refuse with 6.7.12's D19 text before Phase 1 writes. The filed repro gives rc 1 with the same refusal; lib/string.cyr is still 6.6.6's, and `--verify` reads `113 verified, 0 failed`. Before, 6.6.7's string was re-vendored and `--verify` read `112 verified, 1 failed`. Measured on x86_64, under wine and on cass. The cost is one silent extra resolve at such a bump. Rows: `lib_sync_relocks.sh` axes 2 and 2g; `deps_sources_reported.sh` S9; `crossos/cli_dry_pass_mute.tcyr` (x86_64, qemu-aarch64, pi, ecb and ach 9/9; wine and cass 5/5); six mutations RED. Filed beside it, for 6.7.14 (Low): a SIGTERM'd `deps --locked` or dry pass leaves its scratch resolve in the temp dir. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-15 on the 6.7.12 tools lane (l6712-tools @ 88afd900; D19 shipped in
c72b4e15, issues/archived/2026-10-08-deps-before-lib-sync-stamps-new-pin.md). The lane's handoff recorded this as a known note
("the closure files themselves are re-vendored at the new pin before the lock refusal") but did not stage it; the
review asked for it to be filed.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D41 — (a) Refuse before anything is written.
**Severity:** Low — fail-closed (`--verify` and `--locked` both fail, and either named remedy — `lib sync --full`,
`rm <file> && cyrius deps` — clears it), but the refusal's last line, `cyrius.lock is unchanged (it records 6.6.6)`,
reads as "nothing was written" while `lib/` was: `deps --verify` then fails on a file the refusal never named.
**Affects:** a full-vendored project (`lib sync --full`) whose pin moves where the new snapshot changed both a file in
the declared closure and one outside it; 6.7.12 (D19) onward.

## Reproduction

A throwaway `CYRIUS_HOME` holding two snapshots of this tree's `lib/`, 6.6.7 moving one leaf inside the closure
(`string.cyr`) and one outside it (`chrono.cyr`) — the shape of `tests/gates/toolchain/lib_sync_relocks.sh`:

```sh
H=$S/home; mkdir -p $H/versions/6.6.6 $H/versions/6.6.7
cp -r lib $H/versions/6.6.6/lib; cp -r lib $H/versions/6.6.7/lib
echo '# moved in 6.6.7' >> $H/versions/6.6.7/lib/chrono.cyr; echo '# moved in 6.6.7' >> $H/versions/6.6.7/lib/string.cyr
echo 6.6.7 > $H/current
cy() { (cd $S/p && HOME=$S/nohome CYRIUS_HOME=$H CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 cyrius "$@"); }
mkdir -p $S/p; printf '[package]\nname = "r"\nversion = "0.0.1"\ncyrius = "6.6.6"\n\n[deps]\nstdlib = ["syscalls", "string"]\n' > $S/p/cyrius.cyml
cy lib sync --full > /dev/null; cy deps | tail -1
sed -i 's/^cyrius = ".*"/cyrius = "6.6.7"/' $S/p/cyrius.cyml
cy deps; echo "rc=$?"
cmp $S/p/lib/string.cyr $H/versions/6.6.7/lib/string.cyr && echo "lib/string.cyr = 6.6.7's"
cy deps --verify 2>&1 | grep -v '^  ok'
```

Output:

```
cyrius.lock: 113 deps locked
error: cyrius.lock not re-locked: [package].cyrius moved from 6.6.6 to 6.6.7, and lib/ holds 1 file this resolve did not vendor that the 6.6.7 snapshot ships with other bytes:
  lib/chrono.cyr
  cyrius.lock records ONE pin for every row; re-locking would stamp 6.6.7 over these rows. Either:
    cyrius lib sync --full     moves them to 6.6.7 and re-locks (a project that vendors the whole snapshot)
    rm <file> && cyrius deps   drops them from lib/ and the lock
  cyrius.lock is unchanged (it records 6.6.6).
rc=1
lib/string.cyr = 6.6.7's
  FAIL: lib/string.cyr (hash mismatch)
112 verified, 1 failed
```

The refusal names `lib/chrono.cyr` only; `lib/string.cyr` — in the closure, which the refused resolve had already
re-vendored at 6.6.7 — is what `--verify` fails on.

## Root cause

`_dep_pin_move_refused` (`cbt/deps.cyr` ~6789) runs inside `cmd_deps_lock` (~6849), i.e. after the resolve's Phase 1
has already written every closure file into `lib/` from the new pin's snapshot. The triage placed the check there (it
needs the resolve's closure, `_dep_closure`); refusing before Phase 1 writes needs the closure computed by a dry pass
first.

## Proposed fix (the user's call: which of the two)

(a) Compute the closure before Phase 1 writes (a dry closure pass) and run `_dep_pin_move_refused` there, so a refused
resolve writes nothing to `lib/` either; or (b) keep the order and make the refusal say so: name the closure files it
re-vendored at the new pin (`lib/ now holds 6.6.7's lib/string.cyr; deps --verify fails on it until one of the two
remedies`). Gate: `lib_sync_relocks.sh` axis 2 moves `string.cyr` as well (it already does) and asserts either
lib/string.cyr byte-unchanged after the refusal (a) or the refusal naming it (b).
