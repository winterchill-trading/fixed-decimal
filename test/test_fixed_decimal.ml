open! Core
module Decimal = Fixed_decimal.Make ()

let%expect_test "to_string / of_string" =
  List.iter
    [ "0"; "1"; "100"; "-12.5"; "0.001"; "113377.0"; "0.00000001"; "+3.10"; ".5"; "007" ]
    ~f:(fun s ->
      let p = Decimal.of_string s in
      printf "%-12s -> %-12s units=%d\n" s (Decimal.to_string p) (Decimal.to_units p));
  [%expect
    {|
    0            -> 0            units=0
    1            -> 1            units=100000000
    100          -> 100          units=10000000000
    -12.5        -> -12.5        units=-1250000000
    0.001        -> 0.001        units=100000
    113377.0     -> 113377       units=11337700000000
    0.00000001   -> 0.00000001   units=1
    +3.10        -> 3.1          units=310000000
    .5           -> 0.5          units=50000000
    007          -> 7            units=700000000
    |}]
;;

let%expect_test "excess precision truncates toward zero" =
  print_endline (Decimal.to_string (Decimal.of_string "1.123456789"));
  print_endline (Decimal.to_string (Decimal.of_string "-1.123456789"));
  [%expect {|
    1.12345678
    -1.12345678
    |}]
;;

let%expect_test "invalid strings" =
  List.iter [ ""; "-"; "."; "1.2.3"; "abc"; "1e5"; "99999999999" ] ~f:(fun s ->
    printf
      "%S -> %s\n"
      s
      (Option.value_map (Decimal.of_string_opt s) ~default:"None" ~f:Decimal.to_string));
  [%expect
    {|
    "" -> None
    "-" -> None
    "." -> None
    "1.2.3" -> None
    "abc" -> None
    "1e5" -> None
    "99999999999" -> None
    |}]
;;

let%expect_test "arithmetic and rounding" =
  let open Decimal in
  let a = of_string "1.5" in
  let b = of_string "0.25" in
  print_s
    [%sexp
      (a + b : t), (a - b : t), (neg a : t), (scale b ~by:3 : t), (sum [ a; b; b ] : t)];
  print_s
    [%sexp
      (round_down (of_string "1.23456") ~decimals:2 : t)
      , (round_down (of_string "-1.23456") ~decimals:2 : t)
      , (round_nearest (of_string "1.235") ~decimals:2 : t)
      , (round_nearest (of_string "-1.235") ~decimals:2 : t)
      , (round_nearest (of_string "1.2349") ~decimals:2 : t)];
  print_s [%sexp (compare a b : int), (a > b : bool), (Decimal.max a b : t)];
  [%expect
    {|
    (1.75 1.25 -1.5 0.75 2)
    (1.23 -1.23 1.24 -1.24 1.23)
    (1 true 1.5)
    |}]
;;

let%expect_test "json" =
  print_endline
    (Yojson.Safe.to_string (Decimal.yojson_of_t (Decimal.of_string "1891.40")));
  List.iter [ {|"1891.4"|}; "42"; "0.5" ] ~f:(fun s ->
    print_s [%sexp (Decimal.t_of_yojson (Yojson.Safe.from_string s) : Decimal.t)]);
  [%expect {|
    "1891.4"
    1891.4
    42
    0.5
    |}]
;;

let%expect_test "float conversion" =
  print_s
    [%sexp
      (Decimal.of_float 0.1 : Decimal.t)
      , (Decimal.to_float (Decimal.of_string "2.5") : float)];
  [%expect {| (0.1 2.5) |}]
;;
