# A ≤ 8-byte struct goes into a value-form `Result` as its bytes, but binding the payload back to a struct reads it as an address — silent, then SIGSEGV — open

**Status:** 🟡 **OPEN** — verified on 6.7.18 (x86_64), 2026-11-08.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-08, by tanmatra's Rust → Cyrius port (M1), probing `Nucleus { z: u32; a: u32 }` as a `Result` payload for M2
**Reporter:** tanmatra 2.0.0 port
**Cyrius version at time of report:** 6.7.18
**Severity:** **Medium.** It compiles with no diagnostic and crashes at the first field read. A program could equally read
whatever lies at that "address".

## Summary

```cyrius
struct Nuc { z: u32; a: u32; }
fn nuc_new(z, a): Result { var n: Nuc; n.z = z; n.a = a; return Ok(n); }
```

- `Ok(n)` puts the struct's **bytes** in the payload word: `nuc_new(26, 56)` gives `0x380000001a`, which is
  `(56 << 32) | 26`.
- Binding that word to a struct-typed local reads it as the struct's **address**. That happens with
  `var n: Nuc = v;` after `var t, v = nuc_new(..)`, and with `var n: Nuc = nuc_new(..)?;`. Then `n.a` dereferences
  `0x380000001a`.

Neither direction warns. The two halves disagree about what a struct in a word is: its bytes on the way in, an
address on the way out.

## Reproduction

[`repros/2026-11-08-small-struct-result-payload-read-as-address.cyr`](repros/2026-11-08-small-struct-result-payload-read-as-address.cyr):

```sh
cyrius build docs/development/issues/repros/2026-11-08-small-struct-result-payload-read-as-address.cyr /tmp/srp
/tmp/srp; echo "exit=$?"      # payload word 380000001a, then exit=139 on 6.7.18
```

## Proposed fix

Either of these closes it. The second is the more useful one.
1. **Refuse the binding.** `var s: Struct = <untyped word>` and `var s: Struct = f()?` (where `f` returns `Result`)
   become compile errors naming the struct. `Ok(<struct>)` could be refused the same way, as a struct is no payload
   word.
2. **Carry small structs by value.** A struct of 8 bytes or less already round-trips as its bytes, so binding a payload
   word to such a struct copies those bytes into the local's frame storage. A struct over 8 bytes in `Ok(..)` stays
   refused (it can't fit one word), or keeps today's pointer meaning *and says so*.

## Consumer-side workaround

tanmatra will represent `Nucleus` as a packed `u64` word, `z | (a << 32)` (the struct's own bytes), with accessor
functions. That rides a value-form `Result` and `?` as a plain integer.
