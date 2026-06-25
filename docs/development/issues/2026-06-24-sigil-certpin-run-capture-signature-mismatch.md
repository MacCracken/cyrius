# sigil `certpin_core` calls `run_capture` with the wrong (old argv-array) signature — cert-pin-via-openssl is broken

**Discovered:** 2026-06-24 by the v6.2.41 call-arity check (issue
`2026-06-23-call-arity-no-check`) while self-compiling the ecosystem.
**Severity:** High — silently broken security-relevant code (certificate
pinning). No crash at the cyrius gate (the path isn't exercised by
check.sh), but any consumer using sigil's openssl-based pin computation
gets garbage.
**Affects:** sigil (`src/certpin_core.cyr`); folded into `lib/sigil.cyr`.
Surfaced on cyrius 6.2.41.

## Summary

`lib/process.cyr` defines:

```cyrius
fn run_capture(cmd, arg1, arg2, buf, buflen): Result   # runs `cmd arg1 arg2`,
                                                        # writes stdout into buf,
                                                        # returns Ok(bytes_read)
```

`sigil/src/certpin_core.cyr:281` calls it against an **older `run_capture(cmd,
argv)` argv-array API that no longer exists**:

```cyrius
var argv = alloc(24);
store64(argv, cmd);
store64(argv + 8, "-c");
store64(argv + 16, buf);          # buf = the "openssl ... | ... | openssl enc -base64" pipeline
var res = run_capture(cmd, argv); # 2 args, but run_capture takes 5
var output = payload(res);        # treats Ok(bytes_read) as an output pointer
```

So the call (a) passes only 2 of 5 args (`arg2`/`buf`/`buflen` bind garbage),
and (b) misinterprets the `Ok(bytes_read)` Result as the captured output
string. The openssl-pipeline pin computation cannot have worked against the
current `run_capture`.

## Reproduction

The v6.2.41 arity check prints, when sigil's certpin is compiled:

```
warning: 'run_capture' expects 5 arguments, got 2
```

## Root cause

`certpin_core.cyr` predates the `run_capture(cmd, arg1, arg2, buf, buflen)`
signature in `lib/process.cyr` and was never migrated. The other sigil
shell-out sites (`tpm_core`, `dmverity`, `luks`) route through
`agnosys_run_capture(args, buf, buflen, errmsg)` and are unaffected.

## Proposed fix

In `sigil/src/certpin_core.cyr`, rewrite the call to the current API: run
`sh -c "<pipeline>"` via `run_capture(cmd, "-c", <pipeline>, outbuf, outlen)`,
allocate an output buffer, and read the captured bytes from `outbuf` using the
`Ok(bytes_read)` count (not by treating the Result as a pointer). Then re-fold
`lib/sigil.cyr` and re-verify (sigil builds + cross-compiles on all four
targets). Needs sigil-domain judgment about the intended capture buffer + a
cert-pin test, so it is **NOT** bundled into v6.2.41 — its own slot.

## Consumer-side workaround

None — the openssl-pipeline pin path is broken until fixed. Consumers needing
certificate pinning should not rely on `certpin_core`'s openssl computation
until this lands.
