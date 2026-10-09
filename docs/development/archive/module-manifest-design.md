# Cyrius Module & Manifest Design

## Principle

Declare what you need. Say where it is. No resolver. No SAT solver.
The manifest is a map from names to locations. The compiler enforces boundaries.

## cyrius.cyml — The Manifest

```toml
name = "kybernet"
version = "0.9.0"
license = "GPL-3.0-only"
entry = "src/main.cyr"
output = "kybernet"

[deps]
agnostik = { path = "../agnostik/lib" }
agnosys  = { path = "../agnosys/lib" }

[deps.nous]
ark = "nous"
version = "0.3.0"
hash = "a7f3c8e1b..."

[deps.stdlib]
path = "lib"
```

### Rules

1. Every dep has a **name** (the key) and a **location** (path or ark+version+hash)
2. `path` — local directory, resolved relative to project root
3. `ark` — fetch from ark registry, verified by content hash
4. No version ranges. No `>=`. No `~>`. Exact version, exact hash.
5. No transitive deps. If agnostik needs alloc, agnostik declares it. You don't inherit it.
6. The manifest is **flat**. One level. No dep-of-dep resolution.

### Why no resolver

A resolver solves the problem: "I want X >= 1.0 and Y >= 2.0, but X needs Y < 2.5."
Cyrius doesn't have that problem because:
- You pin exact versions
- Deps don't pull in other deps transitively
- If two deps need different versions of the same thing, that's your problem to fix explicitly

This is the Plan 9 / Zig philosophy: the human decides, the tool verifies.

## Source: `use` and `pub`

### Declaring a module

A module is a directory of `.cyr` files. The directory name IS the module name.
No `mod` keyword needed to declare — the filesystem is the declaration.

```
kybernet/
  cyrius.cyml
  src/
    main.cyr          # entry point
  lib/                # vendored stdlib (dep: stdlib)
    alloc.cyr
    string.cyr
    vec.cyr
    ...
```

The `mod` keyword still works for **inline modules** (single-file, no directory):

```cyrius
mod math;
pub fn add(a, b) { return a + b; }
pub fn mul(a, b) { return a * b; }

mod main;
use math.add;
var r = add(20, 22);
```

### Importing from deps

```cyrius
# Import a specific function
use agnostik.agent_new;
use agnostik.agent_run;

# Then call with short name
var a = agent_new("worker");
agent_run(a);
```

The compiler resolves `use agnostik.agent_new` by:
1. Looking up `agnostik` in `cyrius.cyml` deps → finds `path = "../agnostik/lib"`
2. Scanning that directory for `pub fn agent_new`
3. Creating the name alias (already implemented as mangled names)

### `pub` enforcement

```cyrius
# In agnostik/lib/agent.cyr
pub fn agent_new(name) { ... }      # accessible via `use agnostik.agent_new`
pub fn agent_run(a) { ... }         # accessible
fn internal_helper(a) { ... }       # NOT accessible — no pub, module-private
```

**Rule**: Without `pub`, a function is only callable within its own module.
Calling a non-pub function from outside → compile error.

This is already parsed (token 73 = `pub`). The enforcement is:
- Pass 1: record which functions have `pub` flag (SPUB already exists at 0x8FED0)
- Pass 2: when resolving `use X.fn`, check GPUB — reject if not public

### What `include` becomes

`include` stays for the stdlib vendored in `lib/`. It's textual inclusion — same compilation unit.

`use` is for cross-module imports — different compilation units with visibility boundaries.

```cyrius
# These are part of YOUR compilation unit (textual include)
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"

# These cross module boundaries (visibility-checked imports)
use agnostik.agent_new;
use agnosys.sys_fork;
```

The distinction:
- `include` = "paste this file into my source" (C model, no boundary)
- `use` = "I need this symbol from that module" (enforced boundary)

### Qualified access (future)

Phase 1 (now): `use agnostik.agent_new;` then call `agent_new()` — unqualified after import.

Phase 2 (later): `use agnostik;` then call `agnostik.agent_new()` — qualified access.

Phase 1 is simpler to implement (it's just the existing alias mechanism). Phase 2 requires
the parser to handle `ident.ident` as a function call, which is more work but cleaner at scale.

## cyrius: What changes

### `cyrius build` with deps

```
$ cyrius build

=== kybernet 0.9.0 ===
  resolve agnostik  ../agnostik/lib  (local)
  resolve agnosys   ../agnosys/lib   (local)
  resolve nous      ark cache        (hash OK)
  compile src/main.cyr -> build/kybernet [x86_64]
  59392 bytes
```

Build steps:
1. Read `cyrius.cyml`
2. For each dep:
   - `path`: verify directory exists
   - `ark`: check cache (`~/.cyrius/cache/`), fetch if missing, verify hash
3. Pass dep paths to compiler (as include search paths or pre-scanned symbol tables)
4. Compile

### `cyrius deps` — show dependency map

```
$ cyrius deps

kybernet 0.9.0
  agnostik  ../agnostik/lib   (local, 6 modules)
  agnosys   ../agnosys/lib    (local, 1 module)
  nous      ark:0.3.0         (cached, hash a7f3c8e1b...)
  stdlib    lib/              (vendored, 21 modules)
```

### `ark fetch` — fetch and hash a package

```
$ ark fetch nous 0.3.0

  fetched nous-0.3.0.ark (2.1KB)
  hash: a7f3c8e1b4d2f...
  cached: ~/.cyrius/cache/nous/0.3.0/

Add to cyrius.cyml:
  [deps.nous]
  ark = "nous"
  version = "0.3.0"
  hash = "a7f3c8e1b4d2f..."
```

## Compiler: What changes

### New: dep path resolution

The compiler needs to know where dep modules live. Two approaches:

**Option A — cyrius preprocesses**: cyrius reads `cyrius.cyml`, resolves all dep paths,
and passes a flat list of "module_name=path" to the compiler via a generated file
or command-line mechanism.

**Option B — compiler reads toml**: the compiler itself reads `cyrius.cyml` and
resolves deps.

Option A is simpler and keeps the compiler focused on compilation.
cyrius would generate a `.deps` file:

```
agnostik=../agnostik/lib
agnosys=../agnosys/lib
nous=/home/user/.cyrius/cache/nous/0.3.0/lib
stdlib=lib
```

The compiler reads this file, and when it encounters `use agnostik.agent_new`,
it knows to scan `../agnostik/lib/` for `pub fn agent_new`.

### New: pub enforcement

In pass 2, when resolving a `use MODULE.FUNCTION` statement:
1. Find the function in the module's scanned symbols
2. Check if it has the `pub` flag
3. If not → `error: function 'FUNCTION' is not public in module 'MODULE'`

For functions called without `use` from a different module:
- Already impossible in the current model (name mangling prevents it)
- The mangled name `agnostik_agent_new` is only created when `use agnostik.agent_new` is declared

### New: module-scoped symbols

Currently all symbols are global. With enforcement:
- Pass 1: tag each function with its module name
- Pass 2: when calling a function, check if caller's module matches callee's module
- Cross-module calls require `use` + `pub`

## Migration path

### Phase 1 — Manifest deps (cyrius change only, no compiler change)
- Parse `[deps]` from `cyrius.cyml`
- Verify dep paths exist
- `cyrius deps` command
- `ark fetch` with hash verification
- No compiler changes — deps are still `include`-based

### Phase 2 — pub enforcement (compiler change)
- Enforce `pub` flag: non-pub functions reject cross-module `use`
- Error messages with module context
- All existing crate libs add `pub` to their public APIs

### Phase 3 — Qualified access (compiler change)
- `use agnostik;` imports the module namespace
- `agnostik.agent_new()` syntax in parser
- Dot-access on module names resolved at compile time

### Phase 4 — Separate compilation (compiler change, major)
- Compile each module to `.o` independently
- Link step combines objects
- Symbol tables exported per module
- This is the big one — requires linker work

## Example: kybernet with manifest deps

### cyrius.cyml
```toml
name = "kybernet"
version = "0.9.0"
license = "GPL-3.0-only"
entry = "src/main.cyr"
output = "kybernet"

[deps]
stdlib   = { path = "lib" }
agnostik = { path = "../agnostik/lib" }
agnosys  = { path = "../agnosys/lib" }
```

### src/main.cyr
```cyrius
# Stdlib — textual include (same compilation unit)
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/process.cyr"

# Cross-module imports (visibility-checked)
use agnostik.agent_new;
use agnostik.agent_run;
use agnosys.sys_fork;
use agnosys.sys_waitpid;

fn main() {
    alloc_init();
    var a = agent_new("init");
    var pid = sys_fork();
    if (pid == 0) {
        agent_run(a);
        syscall(SYS_EXIT, 0);
    }
    sys_waitpid(pid, 0, 0);
    return 0;
}
```

## Non-goals

- **No version ranges** — pin exact versions, update manually
- **No transitive deps** — each project declares everything it needs
- **No lock file** — the manifest IS the lock file (exact versions + hashes)
- **No workspace/monorepo support** — one project, one manifest
- **No conditional deps** — if you need it, declare it; if you don't, don't
- **No resolver** — the human resolves conflicts, the tool verifies paths and hashes
