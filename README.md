# fixed-decimal

Fixed-point decimal numbers for trading systems.

Values are stored as an `int` counting units of 10^-8, so arithmetic is exact and
allocation-free. Strings such as `"113377.5"` parse and print without rounding
surprises. Values with more than 8 fractional digits are truncated toward zero on
parse.

Built with [OxCaml](https://oxcaml.org) and the Core library stack.

## API

The library exposes a single module, `Fixed_decimal`:

- `Fixed_decimal.S`: the signature of a fixed-point type.
- `Fixed_decimal.Make ()`: a fresh, distinct fixed-point type. Each application yields
  a type that is incompatible with the others, so prices, sizes and amounts can be kept
  apart at compile time.

A value of type `Make ().t` supports:

- Construction and conversion: `zero`, `one`, `of_int`, `of_units`, `to_units`,
  `of_float`, `to_float`, `of_string`, `of_string_opt`, `to_string`.
- Arithmetic: `+`, `-`, `neg`, `abs`, `scale`, `sum`, and `mul`, `div`, `div_int`
  (truncating toward zero).
- Predicates and ordering: `is_zero`, `is_positive`, `is_negative`, plus the
  `Comparable` interface.
- Rounding: `round_down` (toward zero) and `round_nearest` (half away from zero), each
  to a given number of decimals.
- Serialization: `sexp`, `compare`, `equal`, `hash`, and `yojson` (encoded as a decimal
  string; numeric JSON values are also accepted on input).

## Multiplication and division

Products and quotients are computed on the raw units without overflowing for any
result that fits in the range: `mul` splits both operands into integer and fractional
parts, and `div` uses long division one decimal digit at a time. Both truncate toward
zero, and division by zero raises.

To mix distinct types, e.g. a price times a size giving a notional amount:

```ocaml
module Notional = Fixed_decimal.Product (Price) (Size) (Usd)

let notional = Notional.mul px sz        (* Price.t -> Size.t -> Usd.t *)
let avg_px = Notional.div notional sz    (* Usd.t -> Size.t -> Price.t *)
```

The raw helpers `Fixed_decimal.mul_units` and `Fixed_decimal.div_units` work on unit
counts directly.

## Build

```sh
opam switch create 5.2.0+ox --repos ox=git+https://github.com/oxcaml/opam-repository.git,default
opam install . --deps-only --with-test
dune build && dune test
```
