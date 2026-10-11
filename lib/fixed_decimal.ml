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
  val to_float : t -> float
  val ( + ) : t -> t -> t
  val ( - ) : t -> t -> t
  val neg : t -> t
  val abs : t -> t
  val scale : t -> by:int -> t
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

let units_of_string_opt s =
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
  then None
  else (
    let int_part = String.lstrip int_part ~drop:(Char.equal '0') in
    if String.length int_part > 10
    then None
    else (
      let whole = if String.is_empty int_part then 0 else Int.of_string int_part in
      let frac_part =
        if String.length frac_part > decimals
        then String.prefix frac_part decimals
        else frac_part ^ String.make (decimals - String.length frac_part) '0'
      in
      let units = (whole * units_per_one) + Int.of_string frac_part in
      Some (if negative then Int.neg units else units)))
;;

let pow10 n = Int.pow 10 n

let check_decimals decimals' =
  if decimals' < 0 || decimals' > decimals
  then raise_s [%message "Fixed_decimal: decimals out of range" (decimals' : int)]
;;

module Make () = struct
  module T = struct
    type t = int [@@deriving compare, equal, hash]

    let to_string = units_to_string
    let of_string_opt = units_of_string_opt

    let of_string s =
      match of_string_opt s with
      | Some t -> t
      | None -> raise_s [%message "Fixed_decimal.of_string: invalid decimal" s]
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
      (match of_string_opt s with
       | Some t -> t
       | None ->
         Ppx_yojson_conv_lib.Yojson_conv.of_yojson_error
           "Fixed_decimal.t_of_yojson: invalid decimal string"
           json)
    | `Int i -> of_int i
    | `Float f -> of_float f
    | _ ->
      Ppx_yojson_conv_lib.Yojson_conv.of_yojson_error
        "Fixed_decimal.t_of_yojson: decimal string expected"
        json
  ;;
end
