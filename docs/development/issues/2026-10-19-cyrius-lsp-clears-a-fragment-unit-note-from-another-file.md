# cyrius-lsp clears a clean fragment's unit note when another file of the same unit is opened, though the unit still has errors — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the review of the 6.7.16 tools lane (unit T5,
issues/2026-10-19-cyrius-lsp-compiles-an-include-fragment-alone.md, 7eb1197ea) on ecb and ach; reproduced on x86_64
Linux with the l6716-tools server (cf2b34ef1's tree) by the lane's review-fix step. Not fixed there: the note's place in
the stale bookkeeping is a design change to the unit publish, beyond the review's must-fix list.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 tools review, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Low — an editor's Information line (`checked as part of src/main.cyr, which has 1 error in another
file`) disappears from a clean fragment while its unit still has the error; no diagnostic is wrong, one is lost.
**Kind:** tooling (programs/cyrius-lsp.cyr, `parse_and_send_diagnostics`).

## Reproduction

A project whose entry `src/main.cyr` includes `src/a.cyr`, `src/b.cyr` and `src/d.cyr`; only `d.cyr` has an error:

```sh
cyrius.cyml:   [package] name = "lspfrag" version = "0.1.0"   [build] entry = "src/main.cyr"
src/main.cyr:  include "src/a.cyr" / include "src/b.cyr" / include "src/d.cyr" / syscall(60, total_b());
src/a.cyr:     var shared_x = 40;  fn helper_a(): i64 { return 2; }
src/b.cyr:     fn total_b(): i64 { return shared_x + helper_a(); }
src/d.cyr:     var d1 = 1;  var bad = nope_d + 1;
```

The server (cycc(programs/cyrius-lsp.cyr)) run under `env -i HOME=<h> CYRIUS_HOME=<h>/.cyrius PATH=/usr/bin:/bin` with the
tree's cycc and CLI in `<h>/.cyrius/bin`, sent initialize, didOpen b.cyr, didOpen d.cyr, didOpen a.cyr, shutdown, exit.
Its publishDiagnostics, in order (paths relative to the scratch directory):

```text
"uri":"p/src/b.cyr","diagnostics":[{..."severity":3,"source":"cyrius","message":"checked as part of src/main.cyr, which has 1 error in another file"}]}}
"uri":"p/src/d.cyr","diagnostics":[{..."severity":1,"source":"cyrius","message":"undefined variable 'nope_d' (missing include or enum?)"}]}}
"uri":"p/src/d.cyr","diagnostics":[{..."severity":1,...,"message":"undefined variable 'nope_d' (missing include or enum?)"}]}}
"uri":"p/src/b.cyr","diagnostics":[]}}
"uri":"p/src/a.cyr","diagnostics":[{..."severity":3,...,"message":"checked as part of src/main.cyr, which has 1 error in another file"}]}}
"uri":"p/src/d.cyr","diagnostics":[{..."severity":1,...,"message":"undefined variable 'nope_d' (missing include or enum?)"}]}}
```

The 4th line clears b.cyr's note when d.cyr is opened (the unit's compile reused: `unit unchanged on disk, its last
compile reused: src/main.cyr`), and opening a.cyr does not restore it. The same on ecb and ach (the review's
measurement with the HEAD server).

## Root cause

`parse_and_send_diagnostics` (programs/cyrius-lsp.cyr ~2827) records, under the unit key, the open document when its own
list is not empty (`if (own > 0 && streq(key, open_path) == 0)`), and the note `_lsp_unit_note` adds is counted in
`own`. The next publish of the same unit from another file walks those records and publishes an empty list on every
recorded file the compile no longer names (`_lsp_publish_file(_lsp_uri_of(fj), 0, s)`). The note is not a compile
diagnostic — it is made for the open document only — so b.cyr is never "named" by d.cyr's publish, and is cleared.

## Fix direction

Record the open document under the unit key only for its compile diagnostics (`own` less the note), so a note is never
cleared by another file's publish; or have each publish of a unit re-send the note on every recorded clean fragment of
that unit while the unit still has errors elsewhere. A row in tests/gates/toolchain/lsp_fragment_compiles_its_unit.sh:
the reproduction above — b.cyr's last publish is still the note after d.cyr and a.cyr are opened; and, d.cyr fixed on
disk and saved, b.cyr's note is cleared (F8's direction kept).
