> **RESOLVED (v6.2.37) — by RETIREMENT, not gating/dropping the 3 fns.**
> Premise-check found this issue **under-scoped**: the reachable-on-agnos
> hard-error set is **8 constants across 11 fns** (the landlock trio PLUS
> `O_RDONLY/O_WRONLY/O_CREAT/O_TRUNC/O_EXCL` in `mac_read_file`/`mac_write_file`/
> `audit_read_proc_events`/`pam_*`/`luks_write_keyfile`/`ima_*`/`tpm_seal`), and the
> **entire region lines 998–10198 (289 fns / 17 subsystems) is ungated Linux-only**.
> So the issue's Option B (drop 3 fns) would leave the `--agnos` build broken on the
> O_* hard-errors. Root cause: cyrius's `lib/agnosys.cyr` was a **stale
> pre-decomposition snapshot** (frozen 1.4.3) — the real agnosys decomposed into
> agnodrm 1.4.4 + folds (trust→sigil, security/mac/audit→kavach, pam→aegis,
> logging→sakshi, Linux-eccentric→agnodrm), and cyrius's only surviving role
> (uname/sysinfo) is already native in `lib/sys.cyr` (v6.1.28/v6.2.23). **Fix:
> deleted `lib/agnosys.cyr` from the stdlib entirely** (user's call, 2026-06-22).
> cycc self-hosts byte-identical (lib-only); check.sh 92/92; api-surface 5063→4327.
> **Consumer rewire (chakshu/mihi) tracked in agnodrm
> `issues/2026-06-22-cyrius-agnosys-retired-consumer-rewire.md`** (the
> decomposition's home repo owns the ecosystem rewire, not cyrius).

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

## Also missing on agnos: the `O_*` open-flag constants

The agnos-build gap extends beyond the `SYS_*` syscalls to the bare **open flags**. The agnos syscall peer (`lib/syscalls_x86_64_agnos.cyr`) defines the AGNOS-native `AO_*` set (`AO_RDONLY=0x0` / `AO_WRONLY=0x1` / `AO_RDWR=0x2` / `AO_CREAT=0x100` / `AO_TRUNC=0x200` / `AO_APPEND=0x400` / `AO_DIRECTORY=0x800`) but **NOT** the bare `O_RDONLY` / `O_WRONLY` / `O_CREAT` / `O_TRUNC` / `O_EXCL` names (those live only in `syscalls_x86_64_linux.cyr` / `syscalls_macos.cyr`). So any agnos-targeted code referencing `O_*` directly — the Landlock `sys_open(path, O_PATH|O_CLOEXEC, …)` path, or any `open()` with `O_CREAT|O_TRUNC|O_EXCL` — is **undefined on agnos**, the same undefined-symbol class as the `SYS_*` gap above. This is a **prerequisite** for the Landlock fix below (its `sys_open` uses the open-flag surface) and for any agnos consumer doing file create/truncate.

**⚠ The values do NOT all coincide — a naive `#ifdef`-define-`O_*`-to-Linux-values is wrong:**

| flag | Linux | agnos `AO_*` | match? |
|------|-------|--------------|--------|
| `O_RDONLY` | 0 | `AO_RDONLY` 0x0 | ✅ |
| `O_WRONLY` | 1 | `AO_WRONLY` 0x1 | ✅ |
| `O_TRUNC`  | 512 (0x200) | `AO_TRUNC` 0x200 | ✅ |
| `O_CREAT`  | **64 (0x40)** | **`AO_CREAT` 0x100** | ❌ differ |
| `O_EXCL`   | **128 (0x80)** | **(no `AO_*` peer)** | ❌ none |

Defining `O_CREAT`/`O_EXCL` to Linux values on agnos passes the **wrong bits** to agnos `open` (which reads `0x100` = CREAT). **Fix:** define the `O_*` names under `#ifdef CYRIUS_TARGET_AGNOS` mapping to the `AO_*` semantics (`O_CREAT`→0x100, `O_TRUNC`→0x200, `O_RDONLY`→0, `O_WRONLY`→1; **decide `O_EXCL`** — agnos `open` has no exclusive-create flag in the §3.3 `AO_*` table yet, so either add one or map it to a documented no-op/error), OR translate the Linux `O_*` bits → `AO_*` at the `open` boundary — the **`lib/sakshi.cyr`** `O_CREAT`(64)→`AO_CREAT`(0x100) / `O_TRUNC`(512)→`AO_TRUNC`(0x200) mapping is the working precedent.

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
