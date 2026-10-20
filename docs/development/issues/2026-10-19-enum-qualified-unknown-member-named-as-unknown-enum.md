# `Color.NOPE` — a declared enum, a member name declared nowhere — is "undefined variable 'Color'" / "unknown name 'Color' in a const context": the ENUM is blamed, not the member — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 frontend lane (unit F3) while measuring the case-label
refusals of issues/2026-10-18-second-refused-case-label-reported-as-expected-colon.md (a `case Color.NOPE:` row). Not that
issue's surface (which label is reported, not what it says) and unchanged by F3: measured identical on the lane before
F3 (e6c35814f's build/cycc) and after it (x86_64; the frontend, every target).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Low — refused (rc 1) every time; the message names the wrong thing (the enum, which is declared).
**Kind:** bug (diagnostics).

## Reproduction

```cyrius
enum Color { RED, GREEN }
const K = Color.NOPE;
fn main(): i64 { var y = Color.NOPE; return y; }
syscall(60, main() + K);
```
```
error:<source>:2:11: unknown name 'Color' in a const context
error:<source>:3:36: undefined variable 'Color'
```
A case label, `case Color.NOPE:`, says "4:14: unknown name 'Color' in a const context". When the member name IS
declared somewhere else (`var NOPE2 = 1; ... Color.NOPE2`), the same lookup says what is wrong: "'NOPE2' is not a
variant of 'Color'" (3:32).

## Root cause

`_enum_qual_resolve` (src/frontend/parse.cyr) reports a wrong base ("'X' is not an enum") or a wrong variant ("'v' is
not a variant of 'E'") only when the member name resolves to SOME variable (`FINDVAR(S, vn) >= 0`); a member name
declared nowhere returns -1 silently, and each caller then falls back to its undefined-name report for the BASE
(`_ce_enum`'s "unknown name", the factor's "undefined variable").

## Direction

A member name declared nowhere, after a base that IS an enum, is "'NOPE' is not a variant of 'Color'" at the member, in
every context (the factor, a const context, a case label); a base that is not an enum keeps its own report.
Diagnostics only.
