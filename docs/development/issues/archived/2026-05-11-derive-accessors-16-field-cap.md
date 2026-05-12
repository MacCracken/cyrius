# Cyrius: `#derive(accessors)` silently corrupts metadata for structs with > 16 fields

**Filed:** 2026-05-11
**Reporter:** agnos (kernel, v1.28.3 work)
**Cyrius version at time of report:** 5.10.44
**Affected source:** `src/frontend/lex_pp.cyr` — `PP_PARSE_STRUCT_DEF` + `PP_DERIVE_ACCESSORS_BODY`
**Severity:** **Medium** — silent miscompilation. Caller gets generated accessor fns whose byte offsets are wrong; consumer code stores/loads at the wrong slot positions, producing data corruption or crashes that look like unrelated bugs (e.g. CR3=0x2 page fault on first context switch in agnos's case). No diagnostic emitted; the `cyrius build` step succeeds.
**Status:** open. **Expected target:** v5.11.x or v5.12.x.

## Summary

`#derive(accessors)` works correctly for structs with up to 16 fields but silently corrupts the metadata table for structs with 17 or more. The generated accessor functions land at incorrect byte offsets; consumers get plausible-looking code that writes to the wrong fields.

agnos hit this at v1.28.3 when adding `#derive(accessors)` to `struct Process` (22 fields: pid, state, rsp, rip, rax, rbx, rcx, rdx, rsi, rdi, rbp, r8, r9, r10, r11, r12, r13, r14, r15, rflags, cr3, exit_code). `Process_set_cr3(p, 0x1000)` was supposed to write to byte offset 160; instead it wrote to a corrupted offset, leaving `cr3` field unset. Downstream `proc_get_cr3` returned a stale/zero value, the scheduler's CR3 switch wrote it to the CR3 register, and the next instruction fetch faulted with `#PF (CR2=<RIP>, CR3=<wrong value>)`.

## Root cause

`src/frontend/lex_pp.cyr` documents the per-struct metadata layout:

```
S+0x197060: field_names[16][32]  (512 bytes — 16 fields × 32 bytes)
S+0x197260: field_types[16][32]  (512 bytes — 16 fields × 32 bytes)
S+0x197460: offsets[?]
```

The field-name and field-type tables are hard-sized at **16 fields × 32 bytes each**. `PP_PARSE_STRUCT_DEF` iterates the struct body and writes each parsed field into `S + 0x197060 + fc * 32` and `S + 0x197260 + fc * 32`. With no bounds check, the 17th field's name (`fc=16`) writes to `S + 0x197060 + 512` = `S + 0x197260` — **clobbering field_types[0]**. The 18th field clobbers field_types[1], etc.

Then `PP_DERIVE_ACCESSORS_BODY` computes byte offsets from `cumul`, which is incremented per field. For untyped fields the increment is +8. But because the offset table at `S + 0x197460` is also adjacent (and the loop walks all `fc` fields), the corrupted region produces accessor offsets that don't correspond to actual struct positions.

The 22-field case in agnos: fields 17-22 silently overwrite the field_types region with their names. The cumulative offsets stored in the offsets table (`S + 0x197460 + fi * 8`) for those fields read corrupted "type indicator" bytes back when computing field sizes (the `prim_load` block at lines ~95-100 checks `load8(S + 0x197260 + fi * 32) == 105` to detect `i`-prefixed types; with overflowed memory there, the check may succeed or fail unpredictably). Net effect: offsets diverge from `fi * 8` after field 16.

## Reproduction

Minimal program (any cyrius 5.10.x — also tested under 5.10.44):

```cyr
#derive(accessors)
struct S { f0; f1; f2; f3; f4; f5; f6; f7; f8; f9; f10; f11; f12; f13; f14; f15; f16; }

var slot[200];

fn main() {
    var p = &slot;
    S_set_f16(p, 0xCAFE);
    # f16 is the 17th field (0-indexed). Expected offset: 16 * 8 = 128.
    if (load64(p + 128) == 0xCAFE) { syscall(60, 128); }
    syscall(60, 99);   # 99 if cr3 wrote nowhere expected
    return 0;
}

var exit_code = main();
syscall(60, exit_code);
```

Expected behavior: exit code 128 (S_set_f16 wrote to offset 128).
Actual behavior: exit code 99 (S_set_f16 wrote to corrupted offset; not 128).

For the 22-field case agnos hit, the corruption manifests in the kernel's `proc_get_cr3` returning a wrong value, producing a page fault on first context switch. Full diagnosis trail:

```
v=0e e=0010 CR2=0x109ed8 CR3=0x2 RIP=0x109ed8
```

CR3=0x2 came from `proc_get_cr3(new_pid)` returning 2 instead of 0x1000 (the value `proc_create_full` had written via `Process_set_cr3(p, 0x1000)`).

## Suggested fix

Raise the per-struct field cap from 16 to a higher value (32? 64?). Three regions to bump:

```
S+0x197060: field_names[16][32]   → field_names[N][32]
S+0x197260: field_types[16][32]   → field_types[N][32]
S+0x197460: offsets[16] (8B each) → offsets[N]
```

with corresponding region-layout updates downstream (the per-struct tables start at S+0x197500 today — that boundary moves up by `(N-16) * 72` bytes).

Plus add a hard cap check + diagnostic in `PP_PARSE_STRUCT_DEF`:

```cyr
if (fc >= FIELD_CAP) {
    PP_ERROR("too many fields in struct (max ", FIELD_CAP, ")");
    return ip;
}
```

An explicit error is much better than silent miscompilation — a 17th-field overflow loses 14 days of debugging when the symptom is a CR3=0x2 page-fault on context switch, three layers removed from the actual struct decl.

## Agnos-side workaround for v1.28.3

Reverted the `struct Process` `#derive(accessors)` directive and kept consumers on raw `load64`/`store64` against the documented byte offsets. The struct decl stays as documentation. When this cap is raised in cyrius, the accessor port can land in an agnos-side follow-up patch.

agnos's `kernel/core/proc.cyr` comment at the struct decl carries the cross-reference to this issue.

## Notes

- agnos's `struct PciDev` (4 fields) ported cleanly via `#derive(accessors)` in the same v1.28.3 cut. The cap-related bug only fires when a struct exceeds 16 fields.
- agnos's existing pre-1.28.3 consumers (sched.cyr context save/restore, proc.cyr accessor wrappers) are byte-offset code, so they were unaffected once the derive directive was removed.
- This issue is the proximate reason `proc_table` couldn't be ported as part of agnos v1.28.3's struct-refactor slot. Active item #3 in agnos's roadmap stays partly open with this cyrius blocker noted.
- If cyrius would prefer to keep the per-struct memory budget tight, an alternative is to allow `#derive(accessors)` on a smaller-struct *view* of the larger record (i.e. user declares two structs sharing the byte layout). But the cleaner fix is the cap-raise.
