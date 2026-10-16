# `*p = v` with an untyped value into a struct over 8 bytes writes only the first 8 bytes — confirm the reading of decision D4 (a)'s "at sizeof(S) bytes" — OPEN (a decision to confirm)

**Status:** 🟡 **OPEN — a reading for the user to confirm.** Measured 2026-10-14 on the 6.7.11 struct lane's tree
(`l6711-struct` @ `d2dd38fa`), x86_64 and aarch64 (qemu): 72. The lane base (`5fb211da:build/cycc`) also gives 72, so
the 16-byte row's behaviour is unchanged by the lane; what is open is whether the decision asked for more.
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D11 — (a).
**Discovered:** 2026-10-14, the 6.7.11 struct lane's review of the deref-store bite
(issues/archived/2026-10-11-deref-store-through-struct-pointer-decision.md, `2f5387e5` + `8e155bf3`).
**Severity:** P3 — decision wording / documentation. No miscompile: the lane's reading is stated in the guide.

## The decision's text

D4 (a), the user's answer for issues/archived/2026-10-11-deref-store-through-struct-pointer-decision.md: *"Copies sizeof(S)
bytes (0 for a zero-size struct) from any S value that `G = v` takes ... An untyped value is stored as the struct's
word at sizeof(S) bytes, never past the object."*

## The reading the lane shipped

`_dst_word` (`src/frontend/parse.cyr`) stores min(sizeof(S), 8) bytes — the struct's WORD, never past the object — and
the guide (§ Pointers, the `*p = v` paragraph) says so: *"Any other value — an untyped one, an integer — is stored as
the struct's word at `sizeof(S)` bytes, at most 8, never past the object (`*p = 0` clears a 3-byte struct's 3 bytes,
a 16-byte struct's first 8)."* The other reading of "at sizeof(S) bytes" is all sizeof(S) bytes, the value
zero-extended (`*p = 0` would clear a 16-byte struct whole).

## Reproduction

```sh
cat > dw.cyr <<'X'
struct S { a; b; }
fn main(): i64 {
    var s = S { 1, 2 };
    var p: *S = &s;
    *p = 7;
    return s.a * 10 + s.b;
}
syscall(60, main());
X
build/cycc < dw.cyr > dw.bin && chmod +x dw.bin && ./dw.bin; echo "exit $?"
```

Actual: `exit 72` (a = 7, b untouched) on x86_64 and aarch64 (qemu); the lane base the same. Under the
zero-extended reading it would be 70.

## To decide

- (a) Keep the shipped reading: the struct's word, at most 8 bytes (documented). Nothing changes.
- (b) Zero-extend: an untyped value fills all sizeof(S) bytes (the word, then zeros). Changes what `*p = 0` / `*p = 7`
  compute through a pointer to a struct over 8 bytes.
