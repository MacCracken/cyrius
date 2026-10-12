# Struct-packing pattern for C FFI

When `fncallN` can't call a C function directly (struct-by-value
args, float args, variadic, >6 args on aarch64, 8 args on x86_64
SysV — see [`fncall-abi.md`](fncall-abi.md)), the canonical fix is a C shim
that accepts a packed-args struct by pointer. This doc shows the
pattern with examples from mabda's `deps/wgpu_main.c` (mabda's cyrius
side is the folded `lib/mabda.cyr`). Examples 1 and 2 are those shims
as first written; the note under each says what mabda does today.

**Landed:** v5.4.13 (alongside `fncall7` / `fncall8`).

---

## The pattern

```
Cyrius side                   C shim side                   Real C API
───────────                   ───────────                   ──────────
build Args struct       →     accept Args*            →     call real fn with
call fncall2(                 unpack into locals            ABI-correct layout
    shim_fp,                  fill descriptor(s)
    subject,                  invoke the wgpu call
    &args)                    return any result
```

Cyrius always calls the shim via `fncall2(shim_fp, subject_handle,
&args)` — a two-argument call that's always in the safe zone
(scalars only, ≤ 6 args, no floats, no struct-by-value).

---

## Example 1 — `wgpu_shim_buffer_map` (5 args)

Original C API:

```c
void wgpuBufferMapAsync(
    WGPUBuffer buffer,
    WGPUMapMode mode,
    size_t offset,
    size_t size,
    WGPUBufferMapCallbackInfo cb   // struct-by-value → needs shim
);
```

Shim (as first written in `mabda/deps/wgpu_main.c`):

```c
typedef struct {
    WGPUBuffer buffer;
    uint32_t   mode;
    size_t     offset;
    size_t     size;
    long*      status_ptr;
} WgpuMapArgs;

void wgpu_shim_buffer_map(WGPUDevice device, WgpuMapArgs* args) {
    WGPUBufferMapCallbackInfo cb = {
        .mode = WGPUCallbackMode_AllowSpontaneous,
        .callback = c_on_buffer_mapped,
        .userdata1 = args->status_ptr,
    };
    wgpuBufferMapAsync(args->buffer, (WGPUMapMode)args->mode,
                       args->offset, args->size, cb);
    wgpuDevicePoll(device, true, NULL);
}
```

Cyrius caller:

```cyrius
var args = alloc(40);                  # sizeof(WgpuMapArgs)
store64(args + 0,  buffer_handle);
store64(args + 8,  mode);
store64(args + 16, offset);
store64(args + 24, size);
store64(args + 32, &status);
fncall2(_fp(buffer_map_shim), device, args);
```

The same args as a cyrius struct — five 8-byte fields, so the same
offsets and size (see *Layout* below):

```cyrius
struct WgpuMapArgs { buffer; mode; offset; size; status_ptr; }   # sizeof 40

var args = WgpuMapArgs { buffer_handle, mode, offset, size, &status };
fncall2(_fp(buffer_map_shim), device, &args);
```

**mabda today** (`wgpu_buffer_map_sync` in `lib/mabda.cyr`): the
shim takes `(device, buffer, mode, offset, size,
status_ptr)` as six scalars and is called with `fncall6`. It is still
a shim — it builds the by-value `WGPUBufferMapCallbackInfo` and polls —
but six scalars meet every direct-call condition in
[`fncall-abi.md`](fncall-abi.md), so nothing needs packing. Pack only
past those conditions.

---

## Example 2 — `wgpu_shim_copy_buffer_to_buffer` (6 args)

Original C API takes 6 scalars. As first written, the shim packed
them into `WgpuCopyArgs` for consistency with Example 1:

```c
typedef struct {
    WGPUBuffer src;
    uint64_t   src_off;
    WGPUBuffer dst;
    uint64_t   dst_off;
    uint64_t   size;
} WgpuCopyArgs;

void wgpu_shim_copy_buffer_to_buffer(
    WGPUCommandEncoder encoder, WgpuCopyArgs* args
) {
    wgpuCommandEncoderCopyBufferToBuffer(
        encoder, args->src, args->src_off,
        args->dst, args->dst_off, args->size
    );
}
```

**mabda today** (`wgpu_command_encoder_copy_buffer_to_buffer` in
`lib/mabda.cyr`): this shim is gone — six scalars need none, so mabda
calls `wgpuCommandEncoderCopyBufferToBuffer` directly with `fncall6`.
The packed form above is the shape such a shim takes; a
direct-callable API does not need one.

---

## Example 3 — nested-struct descriptor (the render-pass case)

Original C API:

```c
WGPURenderPassEncoder wgpuCommandEncoderBeginRenderPass(
    WGPUCommandEncoder encoder,
    const WGPURenderPassDescriptor* descriptor
);
```

The descriptor nests a `colorAttachments` array, a
`depthStencilAttachment` sub-struct, and a `timestampWrites`
sub-struct. Building that layout from cyrius would require nested
`alloc` + `store64` sequences that duplicate the C struct layout
and silently break on any wgpu version bump. The shim owns the
layout instead:

```c
typedef struct {
    void*       color_attachments;      // pointer to packed array
    long        color_attachment_count; // i64
    void*       depth_stencil;          // pointer or NULL
    void*       timestamp_writes;       // pointer or NULL
    const char* label;                  // cstr or NULL
} WgpuBeginPassArgs;

WGPURenderPassEncoder wgpu_shim_command_encoder_begin_render_pass(
    WGPUCommandEncoder enc, const WgpuBeginPassArgs* args
) {
    WGPURenderPassDescriptor desc = WGPU_RENDER_PASS_DESCRIPTOR_INIT;
    desc.colorAttachmentCount = args->color_attachment_count;
    desc.colorAttachments = args->color_attachments;
    desc.depthStencilAttachment = args->depth_stencil;
    desc.timestampWrites = args->timestamp_writes;
    if (args->label) {
        desc.label.data = args->label;
        desc.label.length = strlen(args->label);
    }
    return wgpuCommandEncoderBeginRenderPass(enc, &desc);
}
```

Cyrius builds the flat `WgpuBeginPassArgs` and passes `&args` via
`fncall2`. The shim owns all wgpu descriptor layout details.

---

## Design notes

### Layout

Keep the `SomethingArgs` struct layout **flat and stable**. Each
field is one 8-byte slot (pointer or i64 widened from smaller
types). Match cyrius's `store64(args + offset, value)` write
pattern. Don't mix widths or embed sub-structs — the shim unpacks
into the real descriptor.

A cyrius `struct` follows the same rule only when every field is
8 bytes (an untyped field, `i64`, a `*T`, `cstring`, …). Cyrius lays
fields out in declaration order with **no alignment padding** — a
narrow field (`i8` / `i16` / `i32`) is packed against the next one
(`struct { a: i32; b: i64; }` is 12 bytes, `b` at offset 4) where C
pads to 16 with `b` at 8 — so a narrow cyrius field does not line up
with the C struct. ⚠ `u8` / `u16` / `u32` and `f32` fields are full
8-byte words, so they do not match a narrow C field either. The width
of each field type is in the *Field types* table of
[`cyrius-guide.md`](../guides/cyrius-guide.md#field-types-v6610).

### Lifetime

The `args` pointer is valid **only for the duration of the
`fncall2`**. If the real C API captures the pointer (e.g. async
callback that reads args later), the shim must copy data out of
`*args` before returning. All three examples above satisfy this:
`buffer_map` submits immediately, `copy_buffer_to_buffer` dispatches
synchronously, `begin_render_pass` builds the descriptor locally.

### Error handling

Shims should return an `int64_t` or pointer so cyrius can detect
failure. `void`-returning real APIs become `int wgpu_shim_X(…)`
returning 0 on success and negative on failure (matching cyrius's
syscall return convention). Callers then `assert_eq(r, 0, "…")`.

### Build integration

`cyrius build` compiles cyrius only: no `cyrius.cyml` key names C
sources (`cyrius help manifest` lists every key) and the build
never runs a C compiler. The shims are built with the C toolchain
as part of the C side the program already has — mabda keeps them in
`deps/wgpu_main.c`, its C launcher (see "Satisfying it" in
[`fncall-abi.md`](fncall-abi.md)) — and their addresses reach cyrius
as function pointers. No changes are needed at the cyrius-stdlib
level.

---

## See also

- [`fncall-abi.md`](fncall-abi.md) — direct-vs-shim decision table.
- `lib/fnptr.cyr` — `fncallN` implementations + header comment.
- mabda `docs/issues/2026-04-19-fncall6-wgpu-crash-resolution.md`
  — the case study that surfaced this pattern as a policy (its
  crash's root cause was the `%fs` prerequisite in `fncall-abi.md`,
  not the argument count).
- mabda `deps/wgpu_main.c` — reference implementation of 5+ shims.
