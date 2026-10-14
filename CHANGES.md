# Changelog

All notable changes to this library are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- `S.of_string_or_error` and `S.of_string_exact`; the latter returns an error instead of
  truncating digits past the eighth fractional one.
- `S.div_or_error`, returning an error on a zero divisor.
- `S.mul_round_nearest` and `S.div_round_nearest`, rounding half away from zero, with
  the same functions on `Product` and the raw `mul_units_round_nearest` and
  `div_units_round_nearest`.
- odoc comments on every public value, and a compiled example under `examples/`.
- Complete opam metadata (authors, homepage, bug reports, description, dependency
  bounds).

## 0.1.0

First version, not published to opam.

### Added

- `Fixed_decimal.Make ()`: generative fixed-point types over an immediate `int` counting
  10^-8 units, with sexp, yojson, `Comparable` and hashing.
- Exact `mul` and `div` that never overflow for an in-range result, truncating toward
  zero; `mul_units` and `div_units`; `Product` across three instances.
- Single-pass, allocation-free `of_substring_exn` and `blit_to_bytes`;
  `[@@zero_alloc]` on arithmetic, comparisons, parsing and printing.
- `of_float` with a `lossy` alert; `round_down` and `round_nearest`.
- `Fixed_decimal.Reference`, the original parser and printer kept for property tests.
