# Contributing to Cyrius

## Development Process

1. **Bootstrap**: `sh bootstrap/bootstrap.sh`
2. **Build compiler**: `cat src/main.cyr | ./build/cycc > /tmp/cycc && chmod +x /tmp/cycc`
3. **Make changes** to compiler or libraries
4. **Test**: `sh scripts/check.sh` (self-host + heap audit + .tcyr tests + lint)
5. **Self-host verify**: two-step bootstrap (cycc compiles itself byte-identical)

## Rules

- Every change must pass full audit (`cyrius audit`) with 0 failures
- Self-hosting must remain byte-identical (cycc == cycc)
- No external dependencies — the entire toolchain bootstraps from a 29KB binary
- One change at a time. Test after each change, not after the feature is "done"
- If 3 attempts fail: defer, document root cause, move on

## Code Style

- Functions: `PascalCase` for compiler internals, `snake_case` for libraries
- Comments: `#` prefix, explain *why* not *what*
- No unnecessary abstractions — three similar lines > one premature helper

## License

All contributions are licensed under GPL-3.0-only.
