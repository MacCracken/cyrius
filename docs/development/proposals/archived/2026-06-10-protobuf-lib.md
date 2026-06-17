# Stdlib protobuf lib: `lib/protobuf.cyr` (wire encode/decode)

**Filed:** 2026-06-10 during hoosh 2.3.5 (OpenTelemetry OTLP span export)
**Severity:** Stdlib gap — hoosh's OTLP exporter wants to speak the standard
OTLP/protobuf wire format to a collector, but Cyrius has no protobuf
encode/decode lib. hoosh shipped an OTLP/**JSON** exporter instead (spec-allowed
over OTLP/HTTP, built with `str_builder`), but most collectors and the broader
OTel ecosystem default to protobuf, and several other AGNOS interop targets
(gRPC services, anything speaking `proto3`) hit the same wall.
**Affects:** new `lib/protobuf.cyr` (pure Cyrius, no syscalls). Consumers:
hoosh (OTLP), and any future gRPC/proto3 client or server in the ecosystem.
**Target slot:** a v6.x stdlib expansion arc, or a same-minor QoL patch — user
direction. No urgency for hoosh (the JSON path works); this unblocks the
*standard* OTLP transport and general protobuf interop.

## Summary

A minimal **proto3 wire-format** encoder/decoder — enough to build and parse
length-delimited messages without a `.proto` compiler. proto3 wire is small and
regular:

| Primitive | Need |
|---|---|
| varint encode/decode | `pb_write_varint(sb, u64)`, `pb_read_varint(buf, pos) -> (val, next)` |
| field tag | `pb_tag(field_no, wire_type)` — `(field_no << 3) \| wire_type` |
| length-delimited (wire 2) | `pb_write_bytes(sb, field_no, ptr, len)` / `pb_write_string` — a varint length prefix then the bytes; used for nested messages + strings |
| fixed64 / fixed32 (wire 1 / 5) | `pb_write_fixed64` / `_fixed32` — little-endian; OTLP uses fixed64 for some timestamps |
| varint field (wire 0) | `pb_write_int(sb, field_no, u64)` — int32/int64/bool/enum |

Decode is the mirror: read a tag, dispatch on wire type, read the value, advance.
Nested messages are just "read a length-delimited field, recurse on the slice."

Build on the existing `str_builder` (encode) + raw `load8`/pointer math (decode),
the same primitives `lib/json.cyr`/bayan already use. No new syscalls, no
allocation beyond what `str_builder` already does.

## Why this is more than cosmetic

1. **OTLP/protobuf is the de-facto standard.** OTLP/HTTP+JSON is spec-allowed but
   the default everywhere (collectors, the OTel SDK exporters, vendor backends)
   is protobuf. hoosh's JSON exporter works against a Collector configured to
   accept `application/json`, but many deployments only enable the protobuf
   receiver. A protobuf encoder lets the gateway speak the format the ecosystem
   actually defaults to.

2. **Hand-rolling per-consumer is the failure mode the stdlib prevents.** Without
   a lib, every consumer that needs protobuf re-implements varint + tag + length
   framing — exactly the kind of fiddly, off-by-one-prone wire code (signed
   zigzag, continuation bits, little-endian fixeds) that belongs in one tested
   place. hoosh chose JSON specifically to *avoid* hand-rolling it.

3. **Unblocks gRPC.** proto3 message framing is the substrate for gRPC. A
   protobuf lib is the first half of any future Cyrius gRPC client/server — OTLP
   is just the first concrete consumer.

## Scope

- **In:** proto3 wire encode/decode of the scalar + length-delimited + nested
  message types (the subset OTLP uses). Hand-authored message builders are fine
  (no `.proto` codegen).
- **Out (later):** a `.proto` → Cyrius code generator; gRPC framing/HTTP2; maps,
  oneofs, packed repeated (add as consumers need them).

## hoosh-side follow-up once this lands

Add an OTLP/protobuf path to `src/lib/otlp.cyr`: build the `TracesData` message
with the lib, POST with `Content-Type: application/x-protobuf`. Select via a
`[[telemetry]] encoding = "protobuf" | "json"` config key (JSON stays the
default until protobuf is proven against real collectors). See hoosh
`docs/decisions/010-observability.md` §"Update (2.3.5)".
