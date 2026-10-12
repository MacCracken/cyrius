# `cyrius init --help`, `cyrius port --help` and `cyrius sign-efi --help` (and `-h`) fail as unknown flags, while `cyrius --help` promises every command takes `--help` — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 on Linux x86_64 against the 6.7.10 slot-open tree (`efb6623f`,
`build/cycc` 2,057,744 B), with the CLI, `cyrius-init` and `cyrsign-efi` built from the tree and a throwaway `HOME` /
`CYRIUS_HOME`. Surveyed `--help` and `-h` on all 39 verbs `cbt/cyrius.cyr` dispatches: 36 print their usage and exit
0; three fail — `init` and `port` print `Unknown flag: --help` (or `-h`) and exit 1; `sign-efi` prints
`cyrsign-efi: unknown option '--help'` and exit 2. `cyrius --help` says "`cyrius <command> --help` lists that
command's flags". (`cyrius help init` prints the general help — `help` ignores a topic other than `manifest`.)
**Placement:** 6.7.12 — repair 2, the CLI lane (roadmap.md § *6.7.12*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (its tools findings: `cyrius init --help`); the survey of every verb
by the 6.7.10 planning lane, which re-verified and filed it.
**Severity:** Low — a help request fails with a non-zero exit on three verbs; the usage text exists (each helper
prints it when run with no operand) but is not reachable by the flag the top-level help names.
**Affects:** the `cyrius` CLI's raw-tail verbs (`init` and `port` → `cyrius-init`, `sign-efi` → `cyrsign-efi`) since
the CLI's own `--help` became universal (`cbt/cli_args.cyr`, 6.6.5); every host.

## Summary

Every verb except three is parsed by `cbt/cli_args.cyr`, which recognises `-h` / `--help` on any verb and prints a
usage generated from the flag table. `init`, `port` and `sign-efi` are RAW-TAIL verbs: their whole tail is forwarded
verbatim to a helper binary, which parses it itself. Neither helper has a `--help` / `-h` arm: `cyrius-init`'s init
and port loops refuse any unknown `-`-token (`Unknown flag:`), and `cyrsign-efi` refuses every `-`-token by design
(6.6.5, so a flag is never taken as an operand). Both helpers already have a usage printer, reached only by the
missing-operand path.

## Reproduction

```sh
# bash; writes only under $W
cd /home/macro/Repos/cyrius
W=$(mktemp -d); mkdir -p "$W/bin" "$W/p" "$W/h" "$W/ch"
build/cycc < cbt/cyrius.cyr > "$W/bin/cyrius" 2>/dev/null && chmod +x "$W/bin/cyrius"
build/cycc < programs/cyrius-init.cyr > "$W/bin/cyrius-init" 2>/dev/null && chmod +x "$W/bin/cyrius-init"
cp build/cycc build/cyrsign-efi "$W/bin/"
cd "$W/p"; export HOME="$W/h" CYRIUS_HOME="$W/ch"
for v in build run check clean test tests bench fuzz coverage doctest smoke soak fmt lint doc vet deny audit \
         api-surface header init port deps update lib distlib package publish install self pulsar capacity lsp \
         hooks sign-efi which version repl help; do
  for h in --help -h; do
    out=$(timeout 20 "$W/bin/cyrius" $v $h </dev/null 2>&1); rc=$?
    case "$out" in Usage:*|"Cyrius Build Tool"*) [ $rc = 0 ] && continue ;; esac
    echo "$v $h: rc=$rc $(printf '%s\n' "$out" | head -1)"
  done
done
"$W/bin/cyrius" --help | grep -n 'command> --help'
"$W/bin/cyrius" help init | head -1
cd /; rm -rf "$W"
```

```
actual:   init --help: rc=1 Unknown flag: --help
          init -h: rc=1 Unknown flag: -h
          port --help: rc=1 Unknown flag: --help
          port -h: rc=1 Unknown flag: -h
          sign-efi --help: rc=2 cyrsign-efi: unknown option '--help'
          sign-efi -h: rc=2 cyrsign-efi: unknown option '-h'
          7:  operand is never dropped. `cyrius <command> --help` lists that
          Cyrius Build Tool
expected: no line for any verb — each prints its usage on stdout and exits 0
```

## Root cause

- `cbt/cli_args.cyr:194-202` `_cli_raw_tail`: `init`, `port`, `sign-efi` skip the CLI parser, so
  `_cli_wants_help` (`:255-259`) never sees their `--help`.
- `programs/cyrius-init.cyr:887` (init's flag loop) and `:1209` (port's): no `--help` / `-h` arm before the
  `Unknown flag:` refusal; the usage printers are `_init_usage` (`:781`) and `_port_usage` (`:1088`).
- `programs/cyrsign-efi.cyr:57-67` `_cse_args_ok`: every `-`-prefixed token is `unknown option`; the usage is
  `_cse_usage` (`:40`).

## Proposed fix

Either in the CLI (a raw-tail verb whose first tail token is `--help` / `-h` prints a usage the CLI keeps beside
the raw-tail list; delegating to the helper with no operand is not it, since that exits 1 / 2), or in each helper
(a `--help` / `-h` arm, checked before the unknown-flag refusal, that prints the existing usage to stdout and exits
0). The helper-side fix is the smaller one and also covers running `cyrius-init` / `cyrsign-efi`
directly; `cyrsign-efi`'s "any `-` token is refused" rule keeps holding for every other token. Row: extend the CLI
argument gate (`tests/gates/toolchain/cli_args_never_dropped.sh`, or a new one) with the survey above — every
dispatched verb, `--help` and `-h`, rc 0 and a usage line, the verb list derived from `cbt/cyrius.cyr`'s dispatch, not
hand-kept. Mutation: drop one helper's arm → its two rows go RED. (`help <topic>` printing the general help is a
separate nicety; not part of this fix unless the lane takes it.)

## Consumer-side workaround

Run `cyrius init` / `cyrius port` / `cyrius sign-efi` with no operand to see the usage (exit 1 / 1 / 2), or read
`cyrius --help`.
