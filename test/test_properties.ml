(* Properties of the unit arithmetic against an exact big-integer reference (zarith). The
   documented range is [-max_value, max_value] units; generators stay inside it and favour
   the ends, where a split product or a long division step would overflow first. *)

open! Core

let scale = Z.of_int 100_000_000
let max_units = Z.of_int Int.max_value
let fits z = Z.leq (Z.neg max_units) z && Z.leq z max_units

(* [Z.div] truncates toward zero, matching the documented rounding. *)
let ref_mul a b = Z.div (Z.mul (Z.of_int a) (Z.of_int b)) scale
let ref_div a b = Z.div (Z.mul (Z.of_int a) scale) (Z.of_int b)

let gen_units =
  let open Quickcheck.Generator in
  weighted_union
    [ 4., Int.gen_incl (-Int.max_value) Int.max_value
    ; 2., Int.gen_incl (-1_000_000_000) 1_000_000_000
    ; 1., Int.gen_incl (Int.max_value - 1000) Int.max_value
    ; 1., Int.gen_incl (-Int.max_value) (1000 - Int.max_value)
    ; (* Whole numbers, so the fractional partial products are zero. *)
      (1., Int.gen_incl (-46_116_860_184) 46_116_860_184 >>| fun i -> i * 100_000_000)
    ]
;;

(* Largest |x| such that [op a x] stays in range, clamped to the range. *)
let gen_partner ~bound =
  let bound = Z.min bound max_units |> Z.to_int in
  let open Quickcheck.Generator in
  weighted_union
    [ 3., Int.gen_incl (-bound) bound
    ; 1., Int.gen_incl (Int.max 0 (bound - 1000)) bound
    ; 1., Int.gen_incl (-bound) (Int.min 0 (1000 - bound))
    ]
;;

let gen_mul_pair =
  let open Quickcheck.Let_syntax in
  let%bind a = gen_units in
  let bound =
    if a = 0 then max_units else Z.div (Z.mul max_units scale) (Z.abs (Z.of_int a))
  in
  let%map b = gen_partner ~bound in
  a, b
;;

let gen_div_pair =
  let open Quickcheck.Let_syntax in
  let%bind b = Quickcheck.Generator.filter gen_units ~f:(fun b -> b <> 0) in
  let bound = Z.div (Z.mul max_units (Z.abs (Z.of_int b))) scale in
  let%map a = gen_partner ~bound in
  a, b
;;

let check ?(examples = []) name gen ~actual ~expected =
  Quickcheck.test
    gen
    ~sexp_of:[%sexp_of: int * int]
    ~trials:20_000
    ~examples
    ~f:(fun (a, b) ->
      let expected = expected a b in
      (* The generators aim at in-range results; skip the few that miss. *)
      if fits expected
      then (
        let actual = actual a b in
        if not (Z.equal (Z.of_int actual) expected)
        then
          raise_s
            [%message
              name (a : int) (b : int) (actual : int) ~expected:(Z.to_string expected)]))
;;

let%test_unit "mul_units is exact truncated multiplication" =
  check "mul_units" gen_mul_pair ~actual:Fixed_decimal.mul_units ~expected:ref_mul
;;

(* Counterexamples found by this test, kept as fixed examples. *)
let div_examples = [ -4611686018427387599, -4138677411334708711 ]

let%test_unit "div_units is exact truncated division" =
  check
    ~examples:div_examples
    "div_units"
    gen_div_pair
    ~actual:Fixed_decimal.div_units
    ~expected:ref_div
;;

module Price = Fixed_decimal.Make ()
module Size = Fixed_decimal.Make ()
module Usd = Fixed_decimal.Make ()
module Notional = Fixed_decimal.Product (Price) (Size) (Usd)

let%test_unit "Product.mul matches the reference" =
  check
    "Product.mul"
    gen_mul_pair
    ~actual:(fun a b -> Notional.mul (Price.of_units a) (Size.of_units b) |> Usd.to_units)
    ~expected:ref_mul
;;

let%test_unit "Product.div matches the reference" =
  check
    ~examples:div_examples
    "Product.div"
    gen_div_pair
    ~actual:(fun a b -> Notional.div (Usd.of_units a) (Size.of_units b) |> Price.to_units)
    ~expected:ref_div
;;

let%expect_test "most generated pairs are in range" =
  let count gen expected =
    Quickcheck.random_value
      ~seed:(`Deterministic "fixed-decimal")
      (Quickcheck.Generator.list_with_length 1000 gen)
    |> List.count ~f:(fun (a, b) -> fits (expected a b))
  in
  print_s
    [%message
      ""
        ~mul_in_range:(count gen_mul_pair ref_mul : int)
        ~div_in_range:(count gen_div_pair ref_div : int)];
  [%expect {| ((mul_in_range 1000) (div_in_range 1000)) |}]
;;

(* Decimal-like strings: mostly digits with signs, points and junk mixed in, valid printed
   values, and long integer parts around the eleven-digit range edge. *)
let gen_decimal_string =
  let open Quickcheck.Generator in
  let char =
    weighted_union
      [ 10., Char.gen_digit
      ; 1., return '.'
      ; 0.5, return '-'
      ; 0.5, return '+'
      ; 0.3, of_list [ ' '; 'e'; '0'; '"'; ','; '\x00' ]
      ]
  in
  weighted_union
    [ (4., Int.gen_incl 0 24 >>= fun n -> String.gen_with_length n char)
    ; 2., gen_units >>| Fixed_decimal.Reference.units_to_string
    ; ( 1.
      , let%bind.Quickcheck.Generator sign = of_list [ ""; "-"; "+" ] in
        let%bind.Quickcheck.Generator zeros = Int.gen_incl 0 3 in
        let%bind.Quickcheck.Generator int_part =
          Int.gen_incl 10 13 >>= fun n -> String.gen_with_length n Char.gen_digit
        in
        let%map.Quickcheck.Generator frac =
          Int.gen_incl 0 12 >>= fun n -> String.gen_with_length n Char.gen_digit
        in
        sign
        ^ String.make zeros '0'
        ^ int_part
        ^ if String.is_empty frac then "" else "." ^ frac )
    ]
;;

let%test_unit "of_substring_exn agrees with the reference parser" =
  Quickcheck.test
    (Quickcheck.Generator.tuple3
       gen_decimal_string
       String.quickcheck_generator
       String.quickcheck_generator)
    ~sexp_of:[%sexp_of: string * string * string]
    ~trials:50_000
    ~examples:
      [ "", "", ""
      ; "-", "", ""
      ; ".", "", ""
      ; "-.", "", ""
      ; "+-1", "", ""
      ; "1.2.3", "", ""
      ; "46116860184.27387903", "", ""
      ; "46116860184.27387904", "", ""
      ; "-46116860184.27387903", "", ""
      ; "000000000000046116860184.273879039", "", ""
      ; "99999999999", "", ""
      ; "100000000000", "", ""
      ; "5.", "x", "y"
      ; ".5", "1", "2"
      ]
    ~f:(fun (s, prefix, suffix) ->
      let framed = prefix ^ s ^ suffix in
      let actual =
        Option.try_with (fun () ->
          Price.of_substring_exn framed ~pos:(String.length prefix) ~len:(String.length s)
          |> Price.to_units)
      in
      let expected = Fixed_decimal.Reference.units_of_string s in
      let of_string_opt = Option.map (Price.of_string_opt s) ~f:Price.to_units in
      if not
           ([%equal: int option] actual expected
            && [%equal: int option] of_string_opt expected)
      then
        raise_s
          [%message "of_substring_exn" s (actual : int option) (expected : int option)])
;;

let%expect_test "generated decimal strings mix valid, invalid and out of range" =
  Quickcheck.random_value
    ~seed:(`Deterministic "fixed-decimal")
    (Quickcheck.Generator.list_with_length 1000 gen_decimal_string)
  |> List.map ~f:(fun s ->
    match Fixed_decimal.Reference.units_of_string s with
    | Some _ -> "valid"
    | None ->
      (match Price.of_string s with
       | _ -> "valid"
       | exception exn ->
         if String.is_substring (Exn.to_string exn) ~substring:"out of range"
         then "out_of_range"
         else "invalid"))
  |> List.sort_and_group ~compare:String.compare
  |> List.map ~f:(fun group -> List.hd_exn group, List.length group)
  |> [%sexp_of: (string * int) list]
  |> print_s;
  [%expect {| ((invalid 437) (out_of_range 101) (valid 462)) |}]
;;

let%test_unit "to_string and blit_to_bytes agree with the reference printer" =
  let buf = Bytes.create (Price.max_string_length + 8) in
  Quickcheck.test
    (Quickcheck.Generator.tuple2 gen_units (Int.gen_incl 0 8))
    ~sexp_of:[%sexp_of: int * int]
    ~trials:50_000
    ~examples:
      [ 0, 0; 1, 0; -1, 0; 100_000_000, 0; -Int.max_value, 0; Int.max_value, 8; 10, 3 ]
    ~f:(fun (units, pos) ->
      let expected = Fixed_decimal.Reference.units_to_string units in
      let t = Price.of_units units in
      let len = Price.blit_to_bytes t buf ~pos in
      let blitted = Bytes.To_string.sub buf ~pos ~len in
      if not
           (String.equal (Price.to_string t) expected
            && String.equal blitted expected
            && Price.string_length t = String.length expected
            && len <= Price.max_string_length)
      then
        raise_s
          [%message "printer" (units : int) expected (Price.to_string t : string) blitted])
;;
