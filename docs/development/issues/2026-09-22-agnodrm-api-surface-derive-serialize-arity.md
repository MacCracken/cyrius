# `cyrius api-surface` records a derived `<S>_to_json` at arity 1 (it takes `(ptr, sb)`) and never lists `<S>_from_json_str` — OPEN

**Status:** 🟡 **OPEN** — tooling defect; it makes a derive migration read as a BREAKING API change.
**Placement:** unpinned — 6.6.x-line backlog.
**Discovered:** 2026-09-22, while evaluating a `#derive(Serialize)` migration of agnodrm's
hand-rolled serializers.
**Severity:** Low — a misleading snapshot. Consumers whose CI gates on `api-surface` see a false
`BREAKING … removed` for any hand-roll → derive swap, which blocks the migration.
**Affects:** `programs/cyrius_api_surface.cyr` at 6.6.6 (lines ~249–255).

## Summary

The api-surface scanner synthesizes the Serialize-derived fns itself:

```cyr
    # Serialize-derived: <name>_to_json/1 + <name>_from_json/1.
    if (want_serialize == 1) {
        _push_synthesized(..., "_to_json",   0, 0, 1);
        _push_synthesized(..., "_from_json", 0, 0, 1);
    }
```

Codegen has emitted `_to_json(ptr, sb)`, arity 2, since v5.9.31. The derive also emits
`_from_json_str`, which the scanner never lists.

## Reproduction

A scratch project whose `src/main.cyr` is:

```cyr
#derive(accessors)
#derive(Serialize)
struct probe_pt { x; y; }

fn main(): i64 {
    alloc_init();
    var p = alloc(16);
    probe_pt_set_x(p, 3);
    probe_pt_set_y(p, 4);
    var sb = str_builder_new();
    probe_pt_to_json(p, sb);          # two arguments; builds and prints {"x":3,"y":4}
    return 0;
}
var r = main();
sys_exit(r);
```

```
$ cyrius api-surface --scope=project --snapshot=snap.txt --update
snapshot updated: 7 public fns written to snap.txt
$ cat snap.txt
main::main/0
main::probe_pt_from_json/1
main::probe_pt_set_x/2
main::probe_pt_set_y/2
main::probe_pt_to_json/1      <- real arity 2
main::probe_pt_x/1
main::probe_pt_y/1
```

`probe_pt_from_json_str` is absent, yet a reachable call to it builds with exit 0, so it exists.

For agnodrm this meant that swapping `drm_verinfo_to_json(v, sb)` / `update_state_to_json(s, sb)`
for derived ones reported `BREAKING: drm::drm_verinfo_to_json/2, update::update_state_to_json/2`
removed.

## Proposed fix

Synthesize `_to_json` at arity 2 and add `_from_json_str/1`, mirroring `PP_DERIVE_SERIALIZE` in
`src/frontend/lex_pp.cyr`. Better still, derive the list from the preprocessor's own emission so the
two cannot drift again.

## Consumer-side workaround

None needed until a consumer migrates; agnodrm keeps its hand-rolls.
