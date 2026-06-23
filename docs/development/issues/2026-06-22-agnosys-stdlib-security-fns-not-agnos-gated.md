# agnosys stdlib module: `security_*` fns not `CYRIUS_TARGET_AGNOS`-gated → breaks agnos builds

**Filed:** 2026-06-22 · **Component:** cyrius stdlib `lib/agnosys.cyr` (agnosys v1.4.3) · **Severity:** blocks `--agnos` builds of agnosys consumers · **Driver:** hands-off surface (filed by the agnos/agnosticos side per the cyrius hands-off rule)

## Summary

The cyrius-stdlib `agnosys` module agnos-gates its **syscall-binding + uname/sysinfo** surface (18 `#ifdef CYRIUS_TARGET_AGNOS` blocks, all at or before line ~627) but leaves its three **Linux-MAC security functions ungated**. Any `cyrius build --agnos` that pulls `agnosys` — *even transitively and even when the consumer only wants `agnosys_uname`* — fails to compile, because the whole module is parsed and the security functions reference Linux-only syscalls that don't exist on AGNOS.

## Repro / impact

```
cd /home/macro/Repos/chakshu && cyrius build --agnos src/main.cyr build/chakshu_agnos
  → error: lib/agnosys.cyr: undefined variable 'SYS_LANDLOCK_CREATE_RULESET'
```

- **chakshu** (system monitor) and **iam** (fastfetch-equivalent) both hit this: they don't call any `security_*` fn, they pull `agnosys` only because **mihi**'s bundle references `agnosys_uname` (`mihi/src/...:21,319`). `agnosys` therefore lands in their cyrius `stdlib = [...]` chain (the parser needs the full module present; DCE drops the unused code from the *linked binary*, but the *parse/compile* of the module still fails on the undefined syscalls).
- Confirmed against agnosys **v1.4.3**, byte-identical across cyrius **6.2.8 / 6.2.31 / current `~/.cyrius/lib`** — not yet fixed in any released stdlib.

## Root cause

`#ifdef CYRIUS_TARGET_AGNOS` gating stops at line ~627. The three security functions below it use Linux-only syscalls unconditionally:

| Fn | Line (current stdlib) | Linux-only syscalls |
|----|----|----|
| `security_apply_landlock` | 1017 | `SYS_LANDLOCK_CREATE_RULESET` (1027), `SYS_LANDLOCK_ADD_RULE` (1064), `SYS_PRCTL` (1076), `SYS_LANDLOCK_RESTRICT_SELF` (1081) |
| `security_load_seccomp` | 1130 | `SYS_PRCTL`/`PR_SET_NO_NEW_PRIVS` (1143), `SYS_PRCTL`/`PR_SET_SECCOMP` (1154) |
| `security_create_namespace` | 1237 | `SYS_UNSHARE` (1244) |

AGNOS has none of Landlock, seccomp-BPF, or namespaces (all Linux LSM/process facilities); FS confinement / syscall filtering / isolation on AGNOS are the **capability layer's** job.

## Fix — two options

**Option A — gate them (minimal, mirrors the just-shipped kavach precedent).** Wrap each fn body in `#ifndef CYRIUS_TARGET_AGNOS` with a `#ifdef CYRIUS_TARGET_AGNOS` early return. agnosys **already has the exact primitive** — `err_not_supported(feature)` (line 241) — and already uses it for SELinux/AppArmor (lines 1515/1542/1588/1605). So:

```cyrius
fn security_apply_landlock(rules, count): i64 {
    if (count == 0) { return Ok(0); }
    #ifdef CYRIUS_TARGET_AGNOS
    return err_not_supported("LANDLOCK");   # transitional — AGNOS confines via capabilities
    #endif
    #ifndef CYRIUS_TARGET_AGNOS
    … existing body …
    #endif
}
```

…and the same for `security_load_seccomp` → `err_not_supported("SECCOMP")` and `security_create_namespace` → `err_not_supported("NAMESPACES")`.

**Option B — drop them (cleaner, per the agnosys→agnodrm decomposition).** `kavach` 3.5.0 **"internalized agnosys's security backends"** and dropped its agnosys dependency; `kavach/src/security.cyr` is now the canonical home for `security_apply_landlock`/`load_seccomp`/`create_namespace`. So these three are **vestigial** in the cyrius-stdlib `agnosys` module — agnosys's live role narrowed to syscall bindings + uname/sysinfo, which is all the actual consumers (mihi/iam/chakshu) use. Removing them fixes the agnos build *and* completes the decomposition on the stdlib side.

**Recommendation:** Option B (shed the vestigial security code), with Option A as the no-removal fallback.

## Precedent (working reference)

`kavach` **3.5.1** (2026-06-22) applied **Option A** to its internalized copy of these exact three functions — `kavach/src/security.cyr`, verified building clean for both host and `--agnos`. Use it as the template; the line shapes are identical.

## After the fix

A stdlib cut with gated/dropped agnosys → mihi/iam/chakshu re-vendor (`cyrius deps`) and build `--agnos` clean. No consumer-side code change needed (none of them call the security fns).
