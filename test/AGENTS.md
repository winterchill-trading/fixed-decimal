# AGENTS.md: fixed-decimal/test

- `test_fixed_decimal.ml`: expect tests for the API. `test_properties.ml`: Quickcheck
  properties. The file `test_fixed_decimal.ml` is on the obj-magic allowlist because it
  checks that values stay immediate at runtime.
- `must_fail/`: a program that must not compile; `price_as_size.expected` pins the error.
- `readme/`: `check_readme.ml` compares the README code blocks with the tests that copy them.

Run: `opam exec --switch 5.2.0+ox -- dune build --root .. @fixed-decimal/runtest`.

Rules:
- A must-fail error text changes only with the compiler; promote it in its own commit.
- Promote expect output only after reading the diff and after a successful `@runtest` build.
- `Obj.magic` is allowed only in files named in `../.obj-magic-allowlist`, each with a
  reason in that file.
