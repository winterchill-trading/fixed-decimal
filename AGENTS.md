# AGENTS.md: fixed-decimal

## Purpose

Fixed-point decimal numbers for trading systems. A value is an `int` counting 10^-8 units,
so arithmetic is exact and, on the hot paths, allocation-free. It is the number type the
rest of the workspace builds prices and sizes on.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The library `fixed-decimal` (module `Fixed_decimal`): the only interface is `fixed_decimal.mli` (see `lib/AGENTS.md`) |
| `examples/` | `notional.ml`, the worked example from the top of the interface; its output is checked by `dune test` (see `examples/AGENTS.md`) |
| `bench/` | Zero-allocation and speed benchmark (see `bench/AGENTS.md`) |
| `test/` | Expect, property and must-fail tests; `test/readme/` checks the README code blocks (see `test/AGENTS.md`) |
| `.github/` | CI workflow and the shared obj-magic check (see `.github/AGENTS.md`) |
| `README.md` | API, examples, floats, performance, portability, known gaps, releasing |
| `CHANGES.md` | Changelog; an `Unreleased` section for user-visible changes |
| `.obj-magic-allowlist` | Files the obj-magic check may skip, each with a reason |
| `dune-project`, `fixed-decimal.opam.template` | Package metadata; the `.opam` file is generated from them |

## Build, test, docs

Run from this repository. The workspace root is one level up, so every command takes
`--root ..`.

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @fixed-decimal/all
opam exec --switch 5.2.0+ox -- dune build --root .. @fixed-decimal/runtest
opam exec --switch 5.2.0+ox -- dune build --root .. @fixed-decimal/doc
```

Parallel work with another agent: prefix each with `DUNE_BUILD_DIR=_build-fixed-decimal`.

`@doc` builds the odoc API docs. CI fails on any odoc warning, so run it before a change
to a public value is pushed.

Standalone (outside the workspace): the org opam repository is the target (see
`../specs/repos/opam-repository.md`). Until then, `opam install . --deps-only --with-test`
then `dune build`. The OxCaml switch must be created first.

## Conventions

- Format only this repository: `dune build --root .. @fixed-decimal/fmt --auto-promote`.
  Never run `dune fmt` at the workspace root.
- The interface is the contract. Every public value has odoc comments and a test.
- `Fixed_decimal.Make ()` is generative: every application is a distinct type. Do not
  share a `t` between applications.
- Zero-allocation discipline: the hot-path functions carry `[@zero_alloc]`; a must-fail
  test under `test/must_fail/` pins the error text.
- README code blocks are checked verbatim by `test/readme`; edit the block and the test
  together.
- User-visible changes go under `Unreleased` in `CHANGES.md`.
- Lossy float conversions are silenced with `[@alert "-lossy"]` only where a float is
  intended, with a comment.

## Dependencies and dependents

No sibling dependencies. It is the first link of the workspace dependency order:
`fixed-decimal -> exchange-core -> order-book -> exchange-core-engine`. CI pins nothing.

## CI

`.github/workflows/ci.yml`: checkout, the shared `ox-setup` action, `dune build`,
`dune test`, `dune exec examples/notional.exe`, install odoc, build `@doc` with odoc
warnings failing the step, then the reusable obj-magic workflow from `../infra`. The
obj-magic check reads `.obj-magic-allowlist`.

To check a run: one `gh run list --limit 1`, then at most one `gh run watch <id>
--exit-status`. Never poll.

## Pitfalls

- A value is an `int` (63 bits), so the range is about +/- 4.6 * 10^10 in whole units.
  Wider values fail to parse. That is a known, open decision; do not widen it silently.
- `mul_units` and `div_units` wrap silently out of range. Quickcheck generators must bound
  the ratios.
- Aliases in a functor body (`let mul = mul_units`) break `[@@zero_alloc]`; write the bodies
  out. Under `open! Core`, `rem` is not infix; use `Int.rem`.
- `Fixed_decimal.S` types derive no `bin_io`; a stable type over one is its own module.
- A module-level first-class module over `Fixed_decimal.S` needs a `(type a : immediate)`
  annotation, or the layout check fails.
- Releasing is a human step documented in `README.md`. Do not tag or publish from here.

## Where to read more

- `README.md`: API, multiplication and division, floats, performance, portability, known
  gaps, releasing.
- `CHANGES.md`: the release history.
- `../specs/repos/fixed-decimal.md`: status and consumers.
- `../oxcaml-claude-skills/skills/oxcaml-performance/`: zero-allocation method.
- `../oxcaml-claude-skills/skills/oxcaml-modes/`: layout and mode annotations.
- `../oxcaml-claude-skills/AGENTS.md`: workspace-wide guide.
- `../oxcaml-claude-skills/GOTCHAS.md`: the fixed-decimal sections.

## Never do

- Install opam packages that change the compiler or `core`, `base`, `async`, `ppx_jane`
  on the shared `5.2.0+ox` switch. Dry-run first: `opam install --switch 5.2.0+ox --dry-run <pkg>`.
  CI installs `odoc` on its own runner; do not install it into the shared switch.
- Publish, tag or release.
- Poll CI in loops.
