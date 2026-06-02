# `cyriusly cmdtools install starship` clobbers existing user config

**Filed:** 2026-05-20 (during hapi M7 dotfile dogfooding)
**Severity:** Medium — silent data loss; recovery requires `git restore` or `hapi rollback`; affects every consumer that uses a richer-than-default `starship.toml` *and* runs the Cyrius prompt installer.
**Affects:** `cyriusly cmdtools install starship` (current shipping surface). Cyrius compiler unaffected.

## Summary

`cyriusly cmdtools install starship` writes `~/.config/starship.toml` from scratch with only the two Cyrius prompt blocks (`[custom.cyrius_pkg]` + `[custom.cyrius]`), accompanied by a header comment stating *"Everything else uses starship's built-in defaults."*

That assumption — "the user has no other starship config" — is wrong for any consumer who:

1. Maintains their own elaborate starship config (powerline, palettes, language modules), **or**
2. Manages `~/.config/starship.toml` via a dotfile manager (hapi, GNU stow, chezmoi, yadm) where the path is a symlink into a tracked repo.

In case (1), the user's hand-rolled config is silently overwritten — no diff, no prompt, no `.bak`. The install command behaves as if the slot is empty.

In case (2), the symlink itself gets dereferenced-and-overwritten, which **writes through the symlink to the dotfile repo file** — meaning the user's repo content is silently flattened to just the Cyrius blocks. The dotfile-manager's audit trail records nothing (the path is still a symlink to the same target; only the target's bytes changed).

Discovered when merging a Cyrius-blocks-only on-disk `~/.config/starship.toml` with a powerline-style dotfile-repo version for hapi-managed adoption: noticed that re-running the install command would obliterate the powerline config without warning.

## Reproduction

```sh
# Plant a richer config
cat > ~/.config/starship.toml <<'EOF'
format = "$os $directory $character"
palette = "catppuccin_mocha"
[os]
disabled = false
[directory]
format = "[ $path ]($style)"
EOF

stat -c %s ~/.config/starship.toml   # ~150 bytes

cyriusly cmdtools install starship

stat -c %s ~/.config/starship.toml   # ~655 bytes — but file contents are
                                     # now ONLY the Cyrius blocks; the
                                     # format/palette/os/directory sections
                                     # are GONE.
```

Same shape via a hapi-managed symlink:

```sh
ln -sf ~/dotfiles/starship/.config/starship.toml ~/.config/starship.toml
cat ~/dotfiles/starship/.config/starship.toml   # rich powerline config
cyriusly cmdtools install starship
cat ~/dotfiles/starship/.config/starship.toml   # FLATTENED to Cyrius-only
```

The symlink survives; the target file's bytes are replaced.

## Root cause (speculation)

I haven't read the cyriusly source, but the symptom is consistent with the install path doing an unconditional `truncate + write` against the literal `~/.config/starship.toml` resolved path, without:

- Reading the existing file to detect non-Cyrius content,
- Detecting that the path is a symlink (and respecting the dotfile-manager invariant),
- Preserving the rest of the file via a marker-block-replace pattern (cf. `update-alternatives`, `aws-cli`'s credentials manager, kubectl's kubeconfig merger — all of which read-modify-write around delimited managed regions).

Flag as speculation — the Cyrius agent should verify against the actual install handler.

## Proposed fix

Two-tier:

**Tier 1 — refuse to clobber.** Before writing, read the existing file (if any). If non-empty and contains anything outside the `[custom.cyrius_pkg]` / `[custom.cyrius]` block ranges, refuse with a clear diagnostic:

```
error: ~/.config/starship.toml has non-Cyrius content; refusing to overwrite.
  → run `cyriusly cmdtools install starship --merge` to splice the Cyrius
    blocks into the existing file (recommended)
  → or `--force` to overwrite (NOT recommended; backs up to .pre-cyrius.bak)
```

**Tier 2 — `--merge` mode does the right thing.** Read the existing file, locate the `[custom.cyrius_pkg]` / `[custom.cyrius]` blocks if present (replace in place) or append them at EOF (otherwise). Preserve every byte outside those blocks. Additionally, if the file's `format = "..."` string is present and does **not** already reference `${custom.cyrius_pkg}` / `${custom.cyrius}`, surface a warning so the user knows to add the references manually (auto-editing the format string is too brittle — placement is a user-aesthetic decision).

**Tier 3 (defensive) — symlink awareness.** If the resolved path is a symlink, mention the target in the diagnostic so the user knows the repo file is the one at risk. Optional `--respect-symlink` flag could refuse to write through symlinks entirely without `--force`.

The pattern matches the marker-block design in `update-alternatives` and friends — the bar is "you can install + uninstall the Cyrius segments idempotently without touching anything else."

## Consumer-side workaround

Shipped today in hapi's dotfile dogfood (M7) — the `dotfiles/starship/hapi.cyml` manifest carries a comment in the merged `.config/starship.toml` warning that a future reinstall will flatten the file, and that `hapi rollback` or `git checkout` is the recovery path. See:

- `hapi/docs/development/state.md` — M7 dogfood section, post-v0.7.0
- `hapi`'s audit-trail (`~/.local/state/hapi/audit.jsonl`) — records the original link so `hapi rollback` walks back to the pre-flatten state if the user re-applies after the install command runs

Workaround is fragile: it depends on the user re-running `hapi link` (or `hapi sync`) AFTER each `cyriusly cmdtools install starship` invocation to re-establish the symlink to the unflattened repo file — but it does NOT prevent the repo file itself from being flattened in the meantime.

A first-party fix in cyriusly closes the gap entirely.

## Acceptance bar

1. `cyriusly cmdtools install starship` against an empty `~/.config/starship.toml` (the today-shape) keeps working unchanged — current users see no regression.
2. Same command against a non-empty file fails fast with the Tier-1 diagnostic (or merges, if `--merge` becomes the default).
3. `--merge` mode round-trips: install → uninstall → install reaches the same end state as the post-install state, with all non-Cyrius content preserved byte-identically.
4. Symlink-resolved writes either refuse-unless-`--force` or include the resolved target path in the diagnostic.

## Related

- `hapi/docs/development/state.md` — M7 dogfood narrative around starship adoption.
- `cyriusly` install-handler module for starship (path TBD — the Cyrius agent knows where).
