# The 6.7.13 changes beyond the decisions' text — confirm or restore each — RESOLVED

> ✅ **CLOSED BY DECISION at the 6.7.14 open** (the user, 2026-10-16, each item asked as its own keep-or-restore question, D48 – D54): items 1 – 5 are KEPT as 6.7.13 shipped them — the replayed `#inline` `return ret2(..)` in a 9 – 16 B struct fn compiles (D48), a `: i64` async fn forwarding a multi-value call is refused (D49), the replayed `?` caller's 2-name destructure is refused (D50), Windows refuses a pointer word / captured vector into a value-form vector parameter as the other targets do (D51), `var x = (mk1());` binds the struct (D52); item 6 — a string literal is exempt from the typed-pointer warning at every site (D53), fixed in 6.7.14 by [the string-literal / `&a[i]` warning issue](../2026-10-16-typed-pointer-warning-string-literal-and-address-of-subscript.md); item 7 — the lsp loose file publishes no pin error (D54 = D47), fixed in 6.7.14 by [the lsp pin-redirect issue](../2026-10-15-lsp-loose-file-reports-pin-redirect-of-server-cwd-project.md). CHANGELOG [6.7.14]

**Status:** ✅ **CLOSED BY DECISION at the 6.7.14 open** (see the banner). Was: 🟡 **OPEN** — filed 2026-10-16 at the 6.7.13 integration from the release-docs pass (one drafter per lane,
reading each lane's handoff, commits and issues against the decisions asked at the open, D1–D45). Each change below
shipped in 6.7.13 and changes what an existing program does, or makes it stop compiling, in a way no decision's text
names. Each is either a false refusal lifted or parity with a rule that already held elsewhere, so each lane took it;
the user confirms or restores each one (the 6.7.11 / 6.7.12 precedent: those lists were answered at the next open).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (decisions at its open; filed at the 6.7.13
integration, 2026-10-16) — never 7.x.
**Severity:** Low — decisions to confirm, not defects; each change is in CHANGELOG [6.7.13] and
ecosystem-migration § 6.7.13.

## The changes

1. **An `#inline` fn whose body is `return ret2(..);`, replayed inside a 9 – 16 B struct fn, compiles** (34 on every
   target; 6.7.12 refused it "got `this expression`") — MV-11 / MV-11r (08e6bfd3, ade43caa). D22 refuses `ret2` in a
   fn declared to return a struct in every class; the replayed callee's `return` returns from the callee, not from
   the struct fn, and the same callee's `ret2(..);` statement form already compiled. **Keep** (a false refusal
   lifted) **or restore** the refusal.
2. **A `: i64`-declared `async fn` forwarding a multi-value call (`return h(..);`) is refused** too — MV-13
   (102b33c4). D24's text names an UNDECLARED `async fn`; the bite also refuses the declared one, matching 6.7.11's
   literal arm (its second value was lost either way). **Keep or restore.**
3. **A destructure of a replayed `?`'s caller is refused "returns 1 value"** (`var a, b = mid(3);` compiled with a
   false warning and exited 62 on 6.7.12, x86_64) — MV-4 (d187bfad). The triage plan pinned the old behaviour (row
   IR6); the lane followed the issue's own second item instead. **Keep or restore.**
4. **On Windows, a pointer word holding a vector's address or a closure's captured vector passed to a value-form vector
   parameter is refused**, as on x86_64 / aarch64 / cx — `var pv: *f64v2 = &w; lanes(pv)`, `lanes(load64(&pv))`,
   `|k| lanes(b)` ran through 6.7.12 (the by-address ABI took them as the vector, 42 under wine) — VC-6 (5a6bd79b,
   fe1a0447). D30's text covers a vector call result; the scalar word that FAULTED there needed the same refusal.
   **Keep** (target parity) **or restore** the Windows-only acceptance of the two shapes that ran.
5. **`var x = (mk1());` of an 8 B struct binds the struct**, as `var x = mk1();` does — so `x + 1` dispatches `P1_add`
   when it exists and is refused "undefined function 'P1_add'" when it does not; through 6.7.12 the wrapped form was a
   word and `x + 1` added to it (34) — RC-2 (92b35796). The filed issue asked for the binding; the operator
   consequence is no decision's text. Workaround: `var x: i64 = (mk1());` (34). **Keep or restore.**
6. **The typed-pointer warning's new sites (D18) also warn on a string literal into a `*u8`** — `t = "xyz";` and a
   declaration-zone `var p: *u8 = "abc";` (the in-fn declaration already warned) — RC-11 (fd3d5e61). D18 exempted the
   literal 0; a string literal is a pointer and the warning there is a false positive, filed for the fix:
   [the warning's string-literal and `&a[i]` false positives](../2026-10-16-typed-pointer-warning-string-literal-and-address-of-subscript.md)
   (6.7.14). Listed here because it widens a warning on code that compiles.
7. **The language server publishes a pin error on line 1 of a loose file** when the server's working directory has a
   `cyrius.cyml` pinning an uninstalled version (6.7.12 published nothing there) — TL-14 (67516853). Filed for the
   decision: [lsp loose file reports the pin redirect of the server cwd's project](../2026-10-15-lsp-loose-file-reports-pin-redirect-of-server-cwd-project.md)
   (6.7.14). Listed here so the list is whole.

## Acceptance

Each item answered keep or restore at the 6.7.14 open; a restore is a bite in 6.7.14 with its row; a keep closes the
item with a line in CHANGELOG [6.7.14].
