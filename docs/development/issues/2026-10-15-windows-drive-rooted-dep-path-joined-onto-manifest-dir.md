# Windows: a drive-rooted `[deps.X] path` is joined onto the manifest's directory — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-15 by the 6.7.12 tools lane (unit T4) while closing
`issues/archived/2026-10-08-cli-path-and-reporting-leftovers.md` item 1; reproduced under wine with the PE CLI
cross-built from the lane's tree (l6712-tools @ df23b5d6) and with 6.7.11's (a919f439 cbt).
**Placement:** 6.7.13 — repair 3: struct values (tools lane; filed from the 6.7.12 tools lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Severity:** Low — a Windows project cannot name a local dependency by its drive-rooted absolute
path (`path = "C:/deps/foo"` or `"C:\\deps\\foo"`); a relative path and a rooted `/deps/foo` work.
Nothing is vendored wrongly: the resolve fails by name.
**Affects:** the `cyrius` CLI on Windows (cyrius.exe), every release with `[deps.X] path`.

## Reproduction (wine; the same on cass by construction — the join is in cbt/)

```sh
mkdir -p pd/dep/dist pd/proj
printf 'fn pd_f(): i64 { return 3; }\n' > pd/dep/dist/dep.cyr
# DF = the dep dir as a drive path, e.g. Z:/home/you/pd/dep (winepath -w, then \ -> /)
cat > pd/proj/cyrius.cyml <<EOF
[package]
name = "pp"
version = "0.0.1"
language = "cyrius"
cyrius = "6.7.12"

[deps]
stdlib = ["string"]

[deps.dep]
path = "$DF"
modules = ["dist/dep.cyr"]
EOF
cd pd/proj && wine cyrius.exe deps
```

Actual (6.7.12 lane tree, after item 1 gave the PE CLI a real cwd):

```
error: [deps.dep] modules entry "dist/dep.cyr" not found in the local path Z:\home\…\pd\proj/Z:/home/…/pd/dep
0 deps resolved, 1 errors
```

6.7.11: the same, joined onto `./` (`… in the local path ./Z:/home/…/pd/dep`). With `path =
"/home/…/pd/dep"` (rooted, no drive) the same project resolves (`1 deps resolved`).

## Root cause

`cbt/deps.cyr` `_dep_join_path(manifest_dir, rel)` treats only a leading `/` as absolute
(`if (load8(rel) == 47) { return rel; }`), so on Windows a drive-rooted `rel` (`X:/…`, `X:\…`) — and a
UNC `\\server\share\…` — is appended to the manifest's directory. 6.7.12's item 1 taught `_abs_path`
the drive-rooted rule (cbt/deps.cyr, `#ifdef CYRIUS_TARGET_WIN`); `_dep_join_path` was outside that
item's filed surface (`_abs_path`, `_tc_unit_dir`, `_tc_run_env`). The fix is the same rule there
under `#ifdef CYRIUS_TARGET_WIN` (a drive-rooted or `\`-led `rel` returned as given), with a wine row
beside cli_path_reporting_leftovers.sh's W leg and a cass check.
