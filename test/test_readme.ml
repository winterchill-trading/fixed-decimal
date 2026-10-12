(* The README examples, verbatim; test/readme checks that every ocaml block in README.md
   still appears here. *)

open! Core
module Price = Fixed_decimal.Make ()
module Size = Fixed_decimal.Make ()
module Usd = Fixed_decimal.Make ()
module Notional = Fixed_decimal.Product (Price) (Size) (Usd)

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

let%expect_test "rounding toward zero" =
  let third = Price.div Price.one (Price.of_int 3) in
  print_s [%sexp (third : Price.t), (Price.neg third : Price.t)];
  print_s [%sexp (Price.of_string_opt "1.123456789" : Price.t option)];
  [%expect {|
    (0.33333333 -0.33333333)
    (1.12345678)
    |}]
;;

let%expect_test "floats are opt-in" =
  print_s [%sexp (Price.of_float 0.1 [@alert "-lossy"] : Price.t)];
  [%expect {| 0.1 |}]
;;
