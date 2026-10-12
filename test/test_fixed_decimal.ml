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

let%expect_test "mul and div truncate toward zero" =
  let open Decimal in
  List.iter
    [ "1.5", "2"
    ; "-1.5", "0.25"
    ; "1", "3"
    ; "-1", "3"
    ; "2", "-3"
    ; "0.00000001", "0.5"
    ; "113377.5", "0.00012"
    ; "0", "7"
    ]
    ~f:(fun (a, b) ->
      let a = of_string a
      and b = of_string b in
      print_s [%message "" (a : t) (b : t) ~mul:(mul a b : t) ~div:(div a b : t)]);
  [%expect
    {|
    ((a 1.5) (b 2) (mul 3) (div 0.75))
    ((a -1.5) (b 0.25) (mul -0.375) (div -6))
    ((a 1) (b 3) (mul 3) (div 0.33333333))
    ((a -1) (b 3) (mul -3) (div -0.33333333))
    ((a 2) (b -3) (mul -6) (div -0.66666666))
    ((a 0.00000001) (b 0.5) (mul 0) (div 0.00000002))
    ((a 113377.5) (b 0.00012) (mul 13.6053) (div 944812500))
    ((a 0) (b 7) (mul 0) (div 0))
    |}]
;;

let%expect_test "mul and div do not overflow near the range limit" =
  let open Decimal in
  let big = of_units 4_000_000_000_012_345_678 in
  print_s
    [%message
      ""
        ~big_times_one:(mul big one : t)
        ~big_div_one:(div big one : t)
        ~big_times_half:(mul big (of_string "0.5") : t)
        ~big_div_big:(div big big : t)
        ~sqrt_ish:(mul (of_string "200000.5") (of_string "200000.5") : t)
        ~third_of_big:(div big (of_int 3) : t)];
  [%expect
    {|
    ((big_times_one 40000000000.12345678) (big_div_one 40000000000.12345678)
     (big_times_half 20000000000.06172839) (big_div_big 1)
     (sqrt_ish 40000200000.25) (third_of_big 13333333333.37448559))
    |}]
;;

let%expect_test "div_int" =
  let open Decimal in
  print_s
    [%sexp
      (div_int (of_string "10") 3 : t)
      , (div_int (of_string "-10") 3 : t)
      , (div_int (of_string "0.00000005") 2 : t)];
  [%expect {| (3.33333333 -3.33333333 0.00000002) |}]
;;

let%expect_test "division by zero raises" =
  let open Decimal in
  let show f = print_s [%sexp (Or_error.try_with f : t Or_error.t)] in
  show (fun () -> div one zero);
  show (fun () -> div_int one 0);
  [%expect
    {|
    (Error "Fixed_decimal.div_units: division by zero")
    (Error "Fixed_decimal.div_int: division by zero")
    |}]
;;

module Price = Fixed_decimal.Make ()
module Size = Fixed_decimal.Make ()
module Usd = Fixed_decimal.Make ()
module Notional = Fixed_decimal.Product (Price) (Size) (Usd)

let%expect_test "Product mixes instances" =
  let px = Price.of_string "113377.5"
  and sz = Size.of_string "-0.00123" in
  let notional = Notional.mul px sz in
  print_s
    [%message
      ""
        (notional : Usd.t)
        ~avg_px:(Notional.div notional sz : Price.t)
        ~raw:(Fixed_decimal.mul_units 150_000_000 200_000_000 : int)
        ~raw_div:(Fixed_decimal.div_units 100_000_000 300_000_000 : int)];
  [%expect
    {| ((notional -139.454325) (avg_px 113377.5) (raw 300000000) (raw_div 33333333)) |}]
;;

let%expect_test "integer parts beyond 10 digits" =
  let show s =
    printf
      "%s -> %s\n"
      s
      (Option.value_map (Decimal.of_string_opt s) ~default:"None" ~f:(fun t ->
         Decimal.to_string t ^ " units=" ^ Int.to_string (Decimal.to_units t)))
  in
  List.iter [ "10974030132.99"; "-10974030132.99" ] ~f:show;
  [%expect
    {|
    10974030132.99 -> 10974030132.99 units=1097403013299000000
    -10974030132.99 -> -10974030132.99 units=-1097403013299000000
    |}]
;;

let%expect_test "range limit: just below and just above max_int units" =
  let show s =
    print_s
      [%sexp (Or_error.try_with (fun () -> Decimal.of_string s) : Decimal.t Or_error.t)]
  in
  List.iter
    [ "46116860184.27387903"
    ; "46116860184.27387904"
    ; "-46116860184.27387903"
    ; "-46116860184.27387904"
    ; "46116860184.99999999999"
    ; "46116860185"
    ; "100000000000"
    ]
    ~f:show;
  [%expect
    {|
    (Ok 46116860184.27387903)
    (Error
     ("Fixed_decimal.of_string: value out of range" 46116860184.27387904
      (max 46116860184.27387903)))
    (Ok -46116860184.27387903)
    (Error
     ("Fixed_decimal.of_string: value out of range" -46116860184.27387904
      (max 46116860184.27387903)))
    (Error
     ("Fixed_decimal.of_string: value out of range" 46116860184.99999999999
      (max 46116860184.27387903)))
    (Error
     ("Fixed_decimal.of_string: value out of range" 46116860185
      (max 46116860184.27387903)))
    (Error
     ("Fixed_decimal.of_string: value out of range" 100000000000
      (max 46116860184.27387903)))
    |}]
;;

let%expect_test "range limit is exact in units" =
  let max = Decimal.of_units Int.max_value in
  print_endline (Decimal.to_string max);
  print_s [%sexp (Decimal.of_string "-46116860184.27387903" |> Decimal.to_units : int)];
  print_s
    [%sexp
      (Decimal.of_string_opt "46116860184.27387903" |> Option.is_some : bool)
      , (Decimal.of_string_opt "46116860184.27387904" |> Option.is_some : bool)];
  [%expect {|
    46116860184.27387903
    -4611686018427387903
    (true false)
    |}]
;;
