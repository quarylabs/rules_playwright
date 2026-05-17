# Spike: Remove Rust CLI and implement in Starlark

## Question
Can `rules_playwright` remove the Rust CLI and run fully in Starlark?

## Short answer
Yes, with moderate refactor cost. There are no fundamental blockers.

## What Rust does today
The Rust binary (used via `//tools/release:cli`) provides 4 subcommands:

1. `workspace`
- Reads `browsers.json` + embedded `download_paths.json`
- Expands browser/platform matrix
- Generates repository BUILD files (`BUILD.bazel`, `aliases/BUILD.bazel`, `browsers/BUILD.bazel`)

2. `http-files`
- Computes `{name, path}` entries for `http_file(...)` repositories

3. `unzip`
- Extracts browser zip archive to output tree artifact

4. `integrity-map`
- Computes SHA256 for browser archives and writes JSON map

## Where Rust is wired in
- `playwright/extensions.bzl` calls CLI `http-files`
- `playwright/repositories.bzl` calls CLI `workspace` and `http-files`
- `playwright/private/unzip_browser.bzl` calls CLI `unzip`
- `playwright/private/integrity_map.bzl` calls CLI `integrity-map`

## Feasibility by feature

### 1) Replace `workspace` and `http-files` with pure Starlark
Feasible.

Repository/module extension code already has everything needed:
- `json.decode` for `browsers.json` and `download_paths.json`
- string formatting/replacement for URL templates
- `ctx.file` / `module_ctx.file` to generate BUILD files

Implementation approach:
- Add a Starlark helper module (e.g. `playwright/private/browser_targets.bzl`) implementing the same target expansion logic currently in `browser_targets.rs`
- Read `download_paths.json` as a normal source file instead of embedding it in a binary
- Return the browser/path structures directly in Starlark
- Write repository files directly from Starlark templates

### 2) Replace `unzip` rule implementation
Feasible.

Current Rust unzip can be replaced with:
- `ctx.actions.run_shell` calling `unzip` (less hermetic), or
- Bazel-provided zipper tool (preferred), if wired as an executable tool dependency.

This is a straightforward rule rewrite.

### 3) Replace `integrity-map`
Feasible.

Can be rewritten as:
- `ctx.actions.run_shell` using `sha256sum`/`shasum` and JSON assembly, or
- small hermetic helper script/tool.

This is the least elegant part in pure Starlark because hashing happens in an action, but it does not require Rust specifically.

## Main risks/tradeoffs

1. Re-implementing matrix logic correctly
- Must preserve behavior around:
  - `-headless-shell` expansion
  - revision overrides per platform
  - platform aliases/groups
  - deterministic sorting

2. Hermeticity for unzip/hash actions
- Need to choose tools carefully to avoid host-dependent behavior.

3. Cross-platform stability
- Existing Rust path is already cross-platform for these operations.
- New shell-based actions need explicit portability handling.

## Benefits of removing Rust

- Simpler contributor setup (no Rust toolchain/crate universe for this repo)
- Smaller release artifact surface (no prebuilt CLI binaries)
- Less moving parts in module lock stability across platforms

## Costs

- One-time refactor of repository generation logic and action tooling
- Need strong regression tests for generated targets and labels

## Recommended migration path

1. Phase 1 (low risk):
- Rewrite `workspace` + `http-files` in Starlark
- Keep Rust only for `unzip` and `integrity-map`

2. Phase 2:
- Replace `unzip` with Starlark action using hermetic unzip tool

3. Phase 3:
- Replace `integrity-map` hashing action

4. Phase 4:
- Remove Rust module/toolchain, CLI sources, and prebuilt artifacts

## Verdict
A fully Starlark implementation is practical and likely worth it if this fork is intended to be the long-term canonical version. The safest way is incremental replacement with parity tests after each phase.
