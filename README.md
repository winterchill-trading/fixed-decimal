# fixed-decimal

Exact fixed-point decimals for OCaml, with 8 fractional digits, stored as an immediate
`int`.

Prices, quantities and money amounts arrive as decimal strings such as `"113377.5"`.
Binary floats cannot hold most of them exactly; `fixed-decimal` stores each value as an
`int` counting units of 10^-8, so addition, comparison and hashing are integer
operations that never allocate, and strings parse and print without rounding surprises.
A generative functor gives each kind of quantity its own type, so a price cannot be
passed where a size is expected. Values with more than 8 fractional digits are truncated
toward zero by `of_string`, or rejected by `of_string_exact`.

Built with [OxCaml](https://oxcaml.org) and the Core library stack; see
[Portability](#portability) for what a plain OCaml 5 build would need.

## API

The library exposes a single module, `Fixed_decimal`:

- `Fixed_decimal.S`: the signature of a fixed-point type.
- `Fixed_decimal.Make ()`: a fresh, distinct fixed-point type. Each application yields
  a type that is incompatible with the others, so prices, sizes and amounts can be kept
  apart at compile time.

A value of type `Make ().t` supports:

- Construction and conversion: `zero`, `one`, `of_int`, `of_units`, `to_units`,
  `of_float`, `to_float`, `of_string`, `of_string_opt`, `of_string_or_error`,
  `of_string_exact` (an error instead of truncating digits past the eighth),
  `to_string`.
- In-place text: `of_substring_exn s ~pos ~len` parses a field inside a larger string
  (a websocket frame, say) and `blit_to_bytes t buf ~pos` writes the decimal into a
  caller's `Bytes` and returns its length; neither allocates. `string_length` and
  `max_string_length` (21) size the buffer.
- Arithmetic: `+`, `-`, `neg`, `abs`, `scale`, `sum`, `mul`, `div`, `div_int`
  (truncating toward zero), `mul_round_nearest`, `div_round_nearest` (half away from
  zero), and `div_or_error`.
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

Where truncation is the wrong rule (fees, averages), `mul_round_nearest` and
`div_round_nearest` round half away from zero instead, and `of_string_exact` refuses a
string that would lose digits:

```ocaml
let%expect_test "rounding to nearest and exact parsing" =
  let two_thirds = Price.div_round_nearest (Price.of_int 2) (Price.of_int 3) in
  print_s [%sexp (two_thirds : Price.t)];
  print_s [%sexp (Price.of_string_exact "1.123456789" |> Result.is_ok : bool)];
  [%expect {|
    0.66666667
    false
    |}]
;;
```

`Product` has the same `mul_round_nearest` and `div_round_nearest`, and the raw helpers
are `mul_units_round_nearest` and `div_units_round_nearest`; a property test holds all of
them to zarith as well.

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

`examples/notional.ml` is the worked example from the top of `fixed_decimal.mli`; it is
built, and its output checked, by `dune test`.

## Build

```sh
opam switch create 5.2.0+ox --repos ox=git+https://github.com/oxcaml/opam-repository.git,default
opam install . --deps-only --with-test
dune build && dune test
```

## Portability

The library needs the OxCaml compiler (`ocaml-variants.5.2.0+ox`) and the Jane Street
`v0.18~preview` packages, which exist only in the
[OxCaml opam repository](https://github.com/oxcaml/opam-repository). OxCaml-only
constructs:

| Construct | Where | Plain OCaml 5 replacement |
| --- | --- | --- |
| `type t : immediate` (layout annotation) | `S.t` | `type t [@@immediate]` |
| `[@@zero_alloc]`, `[@zero_alloc]` | signatures and hot functions | drop (checks only) |
| `let mutable` | parser, printer, long division | `ref` cells (flambda removes them) |
| unboxed tuples `#(a, b)` | printer helper `frac_digits` | a boxed pair or two functions |
| `[@cold]` | error paths | drop (an inlining hint) |

A plain OCaml 5.x build is possible with these mechanical rewrites and a Core v0.17
dependency, at the cost of the allocation checks; none of it is done here. The public
interface uses only the layout annotation and the `[@@zero_alloc]` attributes.

## Known gaps

- The range is that of a 63-bit `int` in 10^-8 units, about +/- 4.6 * 10^10. Larger
  values fail to parse. A wider range needs a second representation (two `int`s or an
  `int64#` pair) and a decision on which instances pay for it, so it is left open.
- The number of fractional digits is fixed at 8 for every instance. A per-instance scale
  (`Make (struct let decimals = 6 end)`) changes every unit helper and would make
  `Product` scale-aware; it is a design change, not a bounded fix.

## Releasing

Not published to opam yet. The planned flow, with
[dune-release](https://github.com/tarides/dune-release):

1. Move the `Unreleased` entries in `CHANGES.md` under a new version heading.
2. `dune-release tag` creates the `v<version>` tag from that heading.
3. `dune-release distrib`, then `dune-release publish` and `dune-release opam pkg` /
   `opam submit` against the OxCaml opam repository (the dependencies do not exist in the
   default opam repository).

The version comes from the tag through `dune subst`; it is not written anywhere else.

## Used by

Inside the same organisation: `exchange-core`, `order-book`, `money`, `market-data`,
`price-anchor`, `equities-core`, the Hyperliquid, Binance and Bybit protocol libraries,
and the simulators and clients built on them.
