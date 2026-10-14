# AGENTS.md: fixed-decimal/lib

`fixed_decimal.ml` and `fixed_decimal.mli` are the whole library. The interface defines
`Fixed_decimal.S` (the signature of a fixed-point type) and the generative `Make ()`.

Build: `opam exec --switch 5.2.0+ox -- dune build --root .. @fixed-decimal/all`.

Rules:
- Changing a signature is a breaking change for every sibling. Add to `S` only with a test
  and an `Unreleased` entry in `../CHANGES.md`.
- Hot-path functions keep `[@zero_alloc]`; if a change breaks it, fix the code, not the
  attribute.
- Keep the file free of I/O and of any dependency beyond `core` and the codec libraries.
