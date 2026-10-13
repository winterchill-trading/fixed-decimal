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
- In-place text: `of_substring_exn s ~pos ~len` parses a field inside a larger string
  (a websocket frame, say) and `blit_to_bytes t buf ~pos` writes the decimal into a
  caller's `Bytes` and returns its length; neither allocates. `string_length` and
  `max_string_length` (21) size the buffer.
- Arithmetic: `+`, `-`, `neg`, `abs`, `scale`, `sum`, and `mul`, `div`, `div_int`
  (truncating toward zero).
- Predicates and ordering: `is_zero`, `is_positive`, `is_negative`, plus the
  `Comparable` interface; `compare`, `equal`, the operators, `min` and `max` are plain
  `int` comparisons.
- Rounding: `round_down` (toward zero) and `round_nearest` (half away from zero), each
  to a given number of decimals.
- Serialization: `sexp`, `compare`, `equal`, `hash`, and `yojson` (encoded as a decimal
  string; numeric JSON values are also accepted on input).

## Example

Each instance of `Make ()` is its own type; `Product` mixes three of them:

```ocaml
module Price = Fixed_decimal.Make ()
module Size = Fixed_decimal.Make ()
module Usd = Fixed_decimal.Make ()
module Notional = Fixed_decimal.Product (Price) (Size) (Usd)
```

```ocaml
let%expect_test "parse, compute, print" =
  let px = Price.of_string "113377.5"
  and sz = Size.of_string "0.00123" in
  let notional = Notional.mul px sz in
  print_endline (Usd.to_string notional);
  print_endline (Price.to_string (Notional.div notional sz));
  print_endline (Price.to_string (Price.round_down px ~decimals:0));
  [%expect {|
    139.454325
    113377.5
    113377
    |}]
;;
```

Passing a `Price.t` where a `Size.t` is expected is a type error;
`test/must_fail` compiles such a file and checks the error.

## Multiplication and division

Products and quotients are computed on the raw units without overflowing for any
result that fits in the range: `mul` splits both operands into integer and fractional
parts, and `div` uses long division one decimal digit at a time. Both truncate toward
zero, and division by zero raises. A property test checks `mul_units`, `div_units` and
`Product` against exact big-integer arithmetic (zarith).

```ocaml
let%expect_test "rounding toward zero" =
  let third = Price.div Price.one (Price.of_int 3) in
  print_s [%sexp (third : Price.t), (Price.neg third : Price.t)];
  print_s [%sexp (Price.of_string_opt "1.123456789" : Price.t option)];
  [%expect {|
    (0.33333333 -0.33333333)
    (1.12345678)
    |}]
;;
```

The raw helpers `Fixed_decimal.mul_units` and `Fixed_decimal.div_units` work on unit
counts directly.

## Floats

`of_float` rounds a binary float to the nearest unit, so it can disagree with the
decimal the float was printed from; it raises on NaN, infinities and values outside the
range, and maps `-0.0` to zero. It carries a `lossy` alert. Prefer `of_string` for wire
values, and silence the alert where a float is intended:

```ocaml
let%expect_test "floats are opt-in" =
  print_s [%sexp (Price.of_float 0.1 [@alert "-lossy"] : Price.t)];
  [%expect {| 0.1 |}]
;;
```

## Performance

`t` is declared `[@@immediate]`: values are unboxed `int`s. The signature marks the
arithmetic (`mul`, `div`, `div_int`, `scale`, rounding), the comparisons,
`of_substring_exn`, `blit_to_bytes`, `string_length`, `mul_units`, `div_units` and
`Product` with `[@@zero_alloc]`, so the compiler rejects a change that makes one of them
allocate (error paths excepted). Expect tests pin the minor words per call with
`Gc.minor_words`. `of_string` uses the same single-pass parser as `of_substring_exn`;
the original string-splitting parser and `sprintf` printer stay as
`Fixed_decimal.Reference`, and quickcheck tests hold the new code to them.

```sh
dune exec bench/bench.exe -- -quota 4
```

`core_bench` on an Apple M-series laptop (arm64; CI runs amd64), in the dev profile,
`--profile release` and release with `OCAMLPARAM='_,O3=1'`. Words are minor words per
call, net of the harness's own 3 (the empty closure row):

| Operation | dev | release | `-O3` | Words |
| --- | ---: | ---: | ---: | ---: |
| `mul` | 6 ns | 5 ns | 5 ns | 0 |
| `div` | 30 ns | 23 ns | 23 ns | 0 |
| `Product.mul` | 7-24 ns | 7 ns | 5 ns | 0 |
| `Product.div` | 24-49 ns | 24 ns | 23 ns | 0 |
| `compare` | 3 ns | 3 ns | 2.5 ns | 0 |
| `of_string "113377.5"` | 20 ns | 18 ns | 16 ns | 0 |
| `of_substring_exn` (price in a frame) | 15-26 ns | 17 ns | 16 ns | 0 |
| `Reference.units_of_string` (old `of_string`) | 85 ns | 85 ns | 69 ns | 14 |
| `to_string` (price) | 24 ns | 22 ns | 23 ns | 3 |
| `blit_to_bytes` (price) | 15 ns | 15 ns | 14 ns | 0 |
| `Reference.units_to_string` (old `to_string`) | 128 ns | 126 ns | 132 ns | 48 |
| empty closure | 2.4 ns | 2.5-4 ns | 2.4 ns | 0 |

Parsing went from 85 ns and 14 words to 18 ns and 0 words; printing from 126 ns and 48
words to 22 ns and 3 words (the result string) or 15 ns and 0 words into a reused
buffer. `div` dropped from 26-31 ns to 23 ns after its long division became a plain
loop. Under 0.5 ns is noise, and these runs shared the machine with other builds.

## Tests

The `ocaml` blocks above are copied verbatim from `test/test_readme.ml`, where they run
as expect tests; `dune test` fails if a block here stops matching that file. (mdx is
not used: the OxCaml opam repository only offers it with an older compiler.)

## Build

```sh
opam switch create 5.2.0+ox --repos ox=git+https://github.com/oxcaml/opam-repository.git,default
opam install . --deps-only --with-test
dune build && dune test
```

CI installs the opam dependencies through the shared
[ox-setup](https://github.com/winterchill-trading/infra/blob/main/docs/ci.md) action, which
caches the built opam switch between runs.
