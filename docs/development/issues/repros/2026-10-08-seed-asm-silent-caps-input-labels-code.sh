#!/bin/sh
# Repro for docs/development/issues/2026-10-08-seed-asm-silent-caps-input-labels-code.md
# Run from the cyrius repo root: sh docs/development/issues/repros/2026-10-08-seed-asm-silent-caps-input-labels-code.sh
# Feeds the seed (bootstrap/asm) three small assembly inputs, one per cap, and runs what it emits.
# Every input exits 42 when assembled correctly.
SEED="$(pwd)/bootstrap/asm"
[ -x "$SEED" ] || { echo "run from the repo root (bootstrap/asm not found)"; exit 2; }
D=$(mktemp -d) && [ -d "$D" ] || exit 2
trap 'rm -rf "$D"' EXIT
cd "$D" || exit 2

run() {   # $1 = name
    "$SEED" < "$1.s" > "$1.bin" 2> "$1.err"; rc=$?
    chmod +x "$1.bin"; ./"$1.bin" 2>/dev/null; out=$?
    printf '%-10s src=%7s B  seed exit=%s  emitted=%6s B  program exit=%s  stderr=[%s]\n' \
        "$1" "$(wc -c < "$1.s")" "$rc" "$(wc -c < "$1.bin")" "$out" "$(tr '\n' ' ' < "$1.err")"
}

# 0 — control
printf '_start:\n    mov rax, 60\n    mov rdi, 42\n    syscall\n' > control.s
run control

# 1 — input > 131072 B: the tail past the cap is dropped, exit 0
{ printf '_start:\n    mov rax, 60\n'
  i=0; while [ $i -lt 2000 ]; do
    printf '# padding comment line to push the tail past the seed input cap .......\n'; i=$((i + 1)); done
  printf '    mov rdi, 42\n    syscall\n'; } > input.s
run input

# 2 — 522 labels (cap 512): early labels' table entries are overwritten
{ printf '_start:\n    jmp lbl5\n'
  i=0; while [ $i -lt 520 ]; do printf 'lbl%d:\n    mov rbx, %d\n' $i $i; i=$((i + 1)); done
  printf 'fin:\n    mov rax, 60\n    mov rdi, 42\n    syscall\n'; } > labels.s
run labels

# 3 — 80,000 B of code (CODE is 65,536 B): the code tail is replaced, exit 0
{ printf '_start:\n    jmp past\n    db "'; head -c 80000 /dev/zero | tr '\0' 'A'
  printf '"\npast:\n    mov rax, 60\n    mov rdi, 42\n    syscall\n'; } > code.s
run code
