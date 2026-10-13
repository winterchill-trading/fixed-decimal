open! Core

module type S = sig
  type t : immediate [@@deriving sexp, compare, equal, hash, yojson]

  include Comparable.S with type t := t

  val decimals : int
  val units_per_one : int
  val zero : t
  val one : t
  val of_units : int -> t [@@zero_alloc]
  val to_units : t -> int [@@zero_alloc]
  val of_int : int -> t [@@zero_alloc]
  val of_string : string -> t
  val of_string_opt : string -> t option
  val of_substring_exn : string -> pos:int -> len:int -> t [@@zero_alloc]
  val to_string : t -> string
  val max_string_length : int
  val string_length : t -> int [@@zero_alloc]
  val blit_to_bytes : t -> Bytes.t -> pos:int -> int [@@zero_alloc]

  val of_float : float -> t
  [@@alert
    lossy
      "Fixed_decimal.of_float rounds binary floats and raises on NaN, infinity or out of \
       range input; prefer of_string."]

  val to_float : t -> float
  val ( + ) : t -> t -> t [@@zero_alloc]
  val ( - ) : t -> t -> t [@@zero_alloc]
  val neg : t -> t [@@zero_alloc]
  val abs : t -> t [@@zero_alloc]
  val scale : t -> by:int -> t [@@zero_alloc]
  val mul : t -> t -> t [@@zero_alloc]
  val div : t -> t -> t [@@zero_alloc]
  val div_int : t -> int -> t [@@zero_alloc]
  val sum : t list -> t
  val is_zero : t -> bool [@@zero_alloc]
  val is_positive : t -> bool [@@zero_alloc]
  val is_negative : t -> bool [@@zero_alloc]
  val round_down : t -> decimals:int -> t [@@zero_alloc]
  val round_nearest : t -> decimals:int -> t [@@zero_alloc]
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

(* [10^(8 - k)] for [k] fractional digits read, [0 <= k <= 8]. *)
let frac_scale =
  [| 100_000_000; 10_000_000; 1_000_000; 100_000; 10_000; 1_000; 100; 10; 1 |]
;;

(* Same grammar and range as [units_of_string] over [s.[pos] .. s.[pos + len - 1]], in one
   pass and without allocating. Returns [Int.min_value], which is never a valid result
   (the range is symmetric), on malformed or out of range input. The caller has checked
   the bounds. *)
let[@zero_alloc] units_of_substring_or_min s ~pos ~len =
  let stop = pos + len in
  let mutable i = pos in
  let mutable negative = false in
  if i < stop
  then (
    let c = String.unsafe_get s i in
    if Char.equal c '-'
    then (
      negative <- true;
      i <- i + 1)
    else if Char.equal c '+'
    then i <- i + 1);
  (* Integer part: leading zeros are skipped; beyond eleven significant digits the value
     is out of range, so later digits are only validated. *)
  let mutable whole = 0 in
  let mutable significant = 0 in
  let mutable int_digits = 0 in
  let mutable c = if i < stop then Char.to_int (String.unsafe_get s i) else 0 in
  while i < stop && c >= 48 && c <= 57 do
    if significant > 0 || c > 48
    then (
      significant <- significant + 1;
      if significant <= 11 then whole <- (whole * 10) + (c - 48));
    int_digits <- int_digits + 1;
    i <- i + 1;
    if i < stop then c <- Char.to_int (String.unsafe_get s i)
  done;
  (* Fractional part: the first eight digits count, the rest are validated and truncated. *)
  let mutable frac = 0 in
  let mutable frac_digits = 0 in
  if i < stop && c = 46
  then (
    i <- i + 1;
    let mutable continue = true in
    while continue && i < stop do
      let c = Char.to_int (String.unsafe_get s i) in
      if c >= 48 && c <= 57
      then (
        if frac_digits < decimals then frac <- (frac * 10) + (c - 48);
        frac_digits <- frac_digits + 1;
        i <- i + 1)
      else continue <- false
    done);
  if i <> stop || (int_digits = 0 && frac_digits = 0) || significant > 11
  then Int.min_value
  else (
    let frac = frac * Array.unsafe_get frac_scale (Int.min frac_digits decimals) in
    if whole > (Int.max_value - frac) / units_per_one
    then Int.min_value
    else (
      let units = (whole * units_per_one) + frac in
      if negative then -units else units))
;;

let[@cold] raise_parse_error s ~pos ~len =
  let s = String.sub s ~pos ~len in
  match units_of_string s with
  | Error Overflow ->
    raise_s [%message "Fixed_decimal.of_string: value out of range" s ~max:max_string]
  | Ok _ | Error Invalid ->
    raise_s [%message "Fixed_decimal.of_string: invalid decimal" s]
;;

let[@cold] raise_bounds s ~pos ~len =
  raise_s
    [%message
      "Fixed_decimal.of_substring_exn: range outside the string"
        (pos : int)
        (len : int)
        ~length:(String.length s : int)]
;;

(* ["-46116860184.27387903"]; [Int.min_value] units print one digit longer but in the same
   width, ["-46116860184.27387904"]. *)
let max_string_length = 21

(* The printers work on the non-positive magnitude [-|units|], which exists for every
   [int] including [Int.min_value]. *)
let[@zero_alloc] int_digit_count m =
  let mutable m = m in
  let mutable n = 1 in
  while m <= -10 do
    m <- m / 10;
    n <- n + 1
  done;
  n
;;

(* Fractional digits left after dropping trailing zeros, and their value. *)
let[@zero_alloc] frac_digits frac =
  if frac = 0
  then #(0, 0)
  else (
    let mutable f = frac in
    let mutable n = decimals in
    while f % 10 = 0 do
      f <- f / 10;
      n <- n - 1
    done;
    #(n, f))
;;

let[@zero_alloc] units_string_length units =
  let m = if units > 0 then -units else units in
  let #(n_frac, _) = frac_digits (-Int.rem m units_per_one) in
  (if units < 0 then 1 else 0)
  + int_digit_count (m / units_per_one)
  + if n_frac = 0 then 0 else 1 + n_frac
;;

let[@cold] raise_blit_bounds buf ~pos ~needed =
  raise_s
    [%message
      "Fixed_decimal.blit_to_bytes: not enough room"
        (pos : int)
        (needed : int)
        ~length:(Bytes.length buf : int)]
;;

let[@zero_alloc] units_blit_to_bytes units buf ~pos =
  let m = if units > 0 then -units else units in
  let int_part = m / units_per_one in
  let #(n_frac, frac) = frac_digits (-Int.rem m units_per_one) in
  let n_int = int_digit_count int_part in
  let sign = if units < 0 then 1 else 0 in
  let len = sign + n_int + if n_frac = 0 then 0 else 1 + n_frac in
  if pos < 0 || pos > Bytes.length buf - len then raise_blit_bounds buf ~pos ~needed:len;
  if sign = 1 then Bytes.unsafe_set buf pos '-';
  let mutable q = int_part in
  for k = pos + sign + n_int - 1 downto pos + sign do
    Bytes.unsafe_set buf k (Char.unsafe_of_int (48 - Int.rem q 10));
    q <- q / 10
  done;
  if n_frac > 0
  then (
    let start = pos + sign + n_int in
    Bytes.unsafe_set buf start '.';
    let mutable f = frac in
    for k = start + n_frac downto start + 1 do
      Bytes.unsafe_set buf k (Char.unsafe_of_int (48 + (f % 10)));
      f <- f / 10
    done);
  len
;;

let units_to_string_fast units =
  let len = units_string_length units in
  let buf = Bytes.create len in
  ignore (units_blit_to_bytes units buf ~pos:0 : int);
  Bytes.unsafe_to_string ~no_mutation_while_string_reachable:buf
;;

let[@zero_alloc] units_of_substring_exn s ~pos ~len =
  if pos < 0 || len < 0 || pos > String.length s - len then raise_bounds s ~pos ~len;
  let units = units_of_substring_or_min s ~pos ~len in
  if units = Int.min_value then raise_parse_error s ~pos ~len;
  units
;;

let pow10 n = Int.pow 10 n

let[@zero_alloc] mul_units a b =
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

let[@cold] raise_division_by_zero () =
  raise_s [%message "Fixed_decimal.div_units: division by zero"]
;;

let[@zero_alloc] div_units a b =
  if b = 0 then raise_division_by_zero ();
  let sign = if Bool.equal (a < 0) (b < 0) then 1 else -1 in
  let a = Int.abs a
  and b = Int.abs b in
  (* Long division, one decimal digit at a time. [r < b], so [r * 10] can only overflow
     when [b] exceeds [max_value / 10]; such remainders take the slow path, which adds [r]
     ten times modulo [b]. Every sum there stays below [b], so nothing overflows. *)
  let mutable q = a / b in
  let mutable r = a % b in
  for _ = 1 to decimals do
    if r <= Int.max_value / 10
    then (
      let r10 = r * 10 in
      q <- (q * 10) + (r10 / b);
      r <- r10 % b)
    else (
      let mutable digit = 0 in
      let mutable acc = 0 in
      for _ = 1 to 10 do
        if acc >= b - r
        then (
          digit <- digit + 1;
          acc <- acc - (b - r))
        else acc <- acc + r
      done;
      q <- (q * 10) + digit;
      r <- acc)
  done;
  sign * q
;;

let check_decimals decimals' =
  if decimals' < 0 || decimals' > decimals
  then raise_s [%message "Fixed_decimal: decimals out of range" (decimals' : int)]
;;

module Make () = struct
  module T = struct
    type t = int [@@deriving compare, equal, hash]

    let to_string = units_to_string_fast

    let of_string_opt s =
      let units = units_of_substring_or_min s ~pos:0 ~len:(String.length s) in
      if units = Int.min_value then None else Some units
    ;;

    let[@zero_alloc] of_substring_exn s ~pos ~len = units_of_substring_exn s ~pos ~len
    let of_string s = units_of_substring_exn s ~pos:0 ~len:(String.length s)
    let max_string_length = max_string_length
    let[@zero_alloc] string_length t = units_string_length t
    let[@zero_alloc] blit_to_bytes t buf ~pos = units_blit_to_bytes t buf ~pos
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
  let[@zero_alloc] of_units t = t
  let[@zero_alloc] to_units t = t
  let[@zero_alloc] of_int i = i * units_per_one
  let of_float f = Float.iround_nearest_exn (f *. Float.of_int units_per_one)
  let to_float t = Float.of_int t /. Float.of_int units_per_one
  let[@zero_alloc] ( + ) a b = Int.( + ) a b
  let[@zero_alloc] ( - ) a b = Int.( - ) a b
  let[@zero_alloc] neg t = Int.neg t
  let[@zero_alloc] abs t = Int.abs t
  let[@zero_alloc] scale t ~by = Int.( * ) t by
  let[@zero_alloc] mul a b = mul_units a b
  let[@zero_alloc] div a b = div_units a b

  let[@zero_alloc] div_int t n =
    if Int.equal n 0 then raise_s [%message "Fixed_decimal.div_int: division by zero"];
    Int.( / ) t n
  ;;

  let sum = List.fold ~init:0 ~f:Int.( + )
  let[@zero_alloc] is_zero t = Int.equal t 0
  let[@zero_alloc] is_positive t = Int.( > ) t 0
  let[@zero_alloc] is_negative t = Int.( < ) t 0

  let step ~decimals:d =
    check_decimals d;
    pow10 (Int.( - ) decimals d)
  ;;

  let[@zero_alloc] round_down t ~decimals:d =
    let step = step ~decimals:d in
    Int.( * ) (Int.( / ) t step) step
  ;;

  let[@zero_alloc] round_nearest t ~decimals:d =
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
      let units = units_of_substring_or_min s ~pos:0 ~len:(String.length s) in
      (match if units = Int.min_value then units_of_string s else Ok units with
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

module Reference = struct
  let units_of_string s = Result.ok (units_of_string s)
  let units_to_string = units_to_string
end
