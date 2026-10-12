open! Core

module type S = sig
  type t [@@deriving sexp, compare, equal, hash, yojson]

  include Comparable.S with type t := t

  val decimals : int
  val units_per_one : int
  val zero : t
  val one : t
  val of_units : int -> t
  val to_units : t -> int
  val of_int : int -> t
  val of_string : string -> t
  val of_string_opt : string -> t option
  val to_string : t -> string

  val of_float : float -> t
  [@@alert
    lossy
      "Fixed_decimal.of_float rounds binary floats and raises on NaN, infinity or out of \
       range input; prefer of_string."]

  val to_float : t -> float
  val ( + ) : t -> t -> t
  val ( - ) : t -> t -> t
  val neg : t -> t
  val abs : t -> t
  val scale : t -> by:int -> t
  val mul : t -> t -> t
  val div : t -> t -> t
  val div_int : t -> int -> t
  val sum : t list -> t
  val is_zero : t -> bool
  val is_positive : t -> bool
  val is_negative : t -> bool
  val round_down : t -> decimals:int -> t
  val round_nearest : t -> decimals:int -> t
end

let decimals = 8
let units_per_one = 100_000_000

let units_to_string units =
  if units = 0
  then "0"
  else (
    let sign = if units < 0 then "-" else "" in
    let a = Int.abs units in
    let int_part = a / units_per_one in
    let frac_part = a mod units_per_one in
    let frac =
      if frac_part = 0
      then ""
      else "." ^ String.rstrip (sprintf "%08d" frac_part) ~drop:(Char.equal '0')
    in
    sign ^ Int.to_string int_part ^ frac)
;;

type parse_error =
  | Invalid
  | Overflow

let units_of_string s : (int, parse_error) Result.t =
  let negative, body =
    match String.chop_prefix s ~prefix:"-" with
    | Some body -> true, body
    | None -> false, Option.value (String.chop_prefix s ~prefix:"+") ~default:s
  in
  let int_part, frac_part =
    match String.lsplit2 body ~on:'.' with
    | None -> body, ""
    | Some (i, f) -> i, f
  in
  let all_digits x = String.for_all x ~f:Char.is_digit in
  if (String.is_empty int_part && String.is_empty frac_part)
     || (not (all_digits int_part))
     || not (all_digits frac_part)
  then Error Invalid
  else (
    let int_part = String.lstrip int_part ~drop:(Char.equal '0') in
    (* Eleven significant digits already exceed the range, and stopping here keeps
       [Int.of_string] from overflowing. *)
    if String.length int_part > 11
    then Error Overflow
    else (
      let whole = if String.is_empty int_part then 0 else Int.of_string int_part in
      let frac_part =
        if String.length frac_part > decimals
        then String.prefix frac_part decimals
        else frac_part ^ String.make (decimals - String.length frac_part) '0'
      in
      let frac = Int.of_string frac_part in
      (* [whole * units_per_one + frac] fits in an [int] exactly when [whole] is at most
         [(max_value - frac) / units_per_one]. *)
      if whole > (Int.max_value - frac) / units_per_one
      then Error Overflow
      else (
        let units = (whole * units_per_one) + frac in
        Ok (if negative then Int.neg units else units))))
;;

let max_string = units_to_string Int.max_value
let pow10 n = Int.pow 10 n

let mul_units a b =
  let sign = if Bool.equal (a < 0) (b < 0) then 1 else -1 in
  let a = Int.abs a
  and b = Int.abs b in
  (* Split both operands into integer and fractional parts so that every partial product
     stays well inside 63 bits. *)
  let a1 = a / units_per_one
  and a0 = a % units_per_one
  and b1 = b / units_per_one
  and b0 = b % units_per_one in
  sign * ((a1 * b1 * units_per_one) + (a1 * b0) + (a0 * b1) + (a0 * b0 / units_per_one))
;;

let div_units a b =
  if b = 0 then raise_s [%message "Fixed_decimal.div_units: division by zero"];
  let sign = if Bool.equal (a < 0) (b < 0) then 1 else -1 in
  let a = Int.abs a
  and b = Int.abs b in
  (* Long division, one decimal digit at a time, so [r * 10] never overflows. *)
  let rec loop q r digits =
    if digits = 0
    then q
    else (
      let r = r * 10 in
      loop ((q * 10) + (r / b)) (r % b) (digits - 1))
  in
  sign * loop (a / b) (a % b) decimals
;;

let check_decimals decimals' =
  if decimals' < 0 || decimals' > decimals
  then raise_s [%message "Fixed_decimal: decimals out of range" (decimals' : int)]
;;

module Make () = struct
  module T = struct
    type t = int [@@deriving compare, equal, hash]

    let to_string = units_to_string
    let of_string_opt s = Result.ok (units_of_string s)

    let of_string s =
      match units_of_string s with
      | Ok units -> units
      | Error Invalid -> raise_s [%message "Fixed_decimal.of_string: invalid decimal" s]
      | Error Overflow ->
        raise_s [%message "Fixed_decimal.of_string: value out of range" s ~max:max_string]
    ;;

    let sexp_of_t t = Sexp.Atom (to_string t)

    let t_of_sexp = function
      | Sexp.Atom s -> of_string s
      | sexp -> of_sexp_error "Fixed_decimal.t_of_sexp: atom expected" sexp
    ;;
  end

  include T
  include Comparable.Make (T)

  let decimals = decimals
  let units_per_one = units_per_one
  let zero = 0
  let one = units_per_one
  let of_units = Fn.id
  let to_units = Fn.id
  let of_int i = i * units_per_one
  let of_float f = Float.iround_nearest_exn (f *. Float.of_int units_per_one)
  let to_float t = Float.of_int t /. Float.of_int units_per_one
  let ( + ) = Int.( + )
  let ( - ) = Int.( - )
  let neg = Int.neg
  let abs = Int.abs
  let scale t ~by = Int.( * ) t by
  let mul = mul_units
  let div = div_units

  let div_int t n =
    if Int.equal n 0 then raise_s [%message "Fixed_decimal.div_int: division by zero"];
    Int.( / ) t n
  ;;

  let sum = List.fold ~init:0 ~f:Int.( + )
  let is_zero t = Int.equal t 0
  let is_positive t = Int.( > ) t 0
  let is_negative t = Int.( < ) t 0

  let step ~decimals:d =
    check_decimals d;
    pow10 (Int.( - ) decimals d)
  ;;

  let round_down t ~decimals:d =
    let step = step ~decimals:d in
    Int.( * ) (Int.( / ) t step) step
  ;;

  let round_nearest t ~decimals:d =
    let step = step ~decimals:d in
    let half = Int.( / ) step 2 in
    let a = Int.abs t in
    let r = Int.( * ) (Int.( / ) (Int.( + ) a half) step) step in
    if Int.( < ) t 0 then Int.neg r else r
  ;;

  let yojson_of_t t = `String (to_string t)

  let t_of_yojson (json : Yojson.Safe.t) =
    match json with
    | `String s ->
      (match units_of_string s with
       | Ok units -> of_units units
       | Error Invalid ->
         Ppx_yojson_conv_lib.Yojson_conv.of_yojson_error
           "Fixed_decimal.t_of_yojson: invalid decimal string"
           json
       | Error Overflow ->
         Ppx_yojson_conv_lib.Yojson_conv.of_yojson_error
           "Fixed_decimal.t_of_yojson: value out of range"
           json)
    | `Int i -> of_int i
    | `Float f -> of_float f
    | _ ->
      Ppx_yojson_conv_lib.Yojson_conv.of_yojson_error
        "Fixed_decimal.t_of_yojson: decimal string expected"
        json
  ;;
end

module Product (A : S) (B : S) (C : S) = struct
  let mul a b = C.of_units (mul_units (A.to_units a) (B.to_units b))
  let div c b = A.of_units (div_units (C.to_units c) (B.to_units b))
end
