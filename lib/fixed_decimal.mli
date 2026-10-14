(** Fixed-point decimals backed by an [int] counting units of [10^-8].

    Decimal strings (e.g. ["113377.5"]) are the usual wire encoding for prices, sizes and
    amounts. Values parsed with more than 8 fractional digits are truncated toward zero.
    The range is +/- 46116860184.27387903 (the magnitude of [max_int] in units of 10^-8);
    larger values are rejected.

    Each application of {!Make} is a distinct type, and {!Product} multiplies and divides
    across three of them:

    {[
      module Price = Fixed_decimal.Make ()
      module Size = Fixed_decimal.Make ()
      module Usd = Fixed_decimal.Make ()
      module Notional = Fixed_decimal.Product (Price) (Size) (Usd)

      let notional = Notional.mul (Price.of_string "113377.5") (Size.of_string "0.00123")
      (* Usd.to_string notional = "139.454325" *)
    ]}

    [examples/notional.ml] builds this example. *)

open! Core

module type S = sig
  (** A count of [10^-8] units. [t] is an immediate [int] at runtime: values are never
      boxed and arithmetic does not allocate. [sexp] and [yojson] use the decimal string
      of {!to_string}; [t_of_yojson] also accepts JSON integers and (with the rounding of
      {!of_float}) JSON floats. *)
  type t : immediate [@@deriving sexp, compare, equal, hash, yojson]

  include Comparable.S with type t := t

  (** The comparisons of [Comparable.S], restated to carry [[@@zero_alloc]]. *)
  val compare : t -> t -> int
  [@@zero_alloc]

  val equal : t -> t -> bool [@@zero_alloc]
  val ( = ) : t -> t -> bool [@@zero_alloc]
  val ( <> ) : t -> t -> bool [@@zero_alloc]
  val ( < ) : t -> t -> bool [@@zero_alloc]
  val ( <= ) : t -> t -> bool [@@zero_alloc]
  val ( > ) : t -> t -> bool [@@zero_alloc]
  val ( >= ) : t -> t -> bool [@@zero_alloc]
  val min : t -> t -> t [@@zero_alloc]
  val max : t -> t -> t [@@zero_alloc]

  (** Number of fractional decimal digits (8). *)
  val decimals : int

  (** Number of units in [one] (10^8). *)
  val units_per_one : int

  (** [0]. *)
  val zero : t

  (** [1] , i.e. {!units_per_one} units. *)
  val one : t

  (** [of_units n] is [n * 10^-8]; every [int] is a valid unit count. *)
  val of_units : int -> t
  [@@zero_alloc]

  (** The number of [10^-8] units in [t]. *)
  val to_units : t -> int [@@zero_alloc]

  (** [of_int n] is the whole number [n]. It wraps around silently when [n] is outside the
      range. *)
  val of_int : int -> t
  [@@zero_alloc]

  (** Parses a decimal string such as ["-12.5"], ["0.001"] or ["100"]: an optional sign,
      digits, and an optional ['.'] followed by digits (["5."] and [".5"] are accepted).
      Digits beyond the eighth fractional one are truncated toward zero. No exponent, no
      whitespace, no digit separators.

      Raises on malformed input or on a value outside the range. *)
  val of_string : string -> t

  (** [of_string], returning [None] instead of raising. *)
  val of_string_opt : string -> t option

  (** [of_string], returning the error instead of raising. *)
  val of_string_or_error : string -> t Or_error.t

  (** [of_string] without truncation: an error when the string has a non-zero digit after
      the eighth fractional one (["0.000000015"]), so a value that does not fit in [10^-8]
      units is reported instead of silently changed. Trailing zeros are fine
      (["1.0000000000"]). *)
  val of_string_exact : string -> t Or_error.t

  (** [of_substring_exn s ~pos ~len] parses [String.sub s ~pos ~len] with the grammar and
      range of [of_string], in one pass and without allocating, so a frame scanner can
      parse a field in place. Raises on malformed input, on a value outside the range and
      on a range outside [s]. *)
  val of_substring_exn : string -> pos:int -> len:int -> t
  [@@zero_alloc]

  (** Shortest decimal representation without trailing zeros, e.g. ["100"], ["0.001"],
      ["-12.5"]. *)
  val to_string : t -> string

  (** Longest [to_string] result (21 bytes, e.g. ["-46116860184.27387903"]). *)
  val max_string_length : int

  (** [String.length (to_string t)], without allocating. *)
  val string_length : t -> int
  [@@zero_alloc]

  (** [blit_to_bytes t buf ~pos] writes [to_string t] into [buf] at [pos] and returns the
      number of bytes written, without allocating. A buffer of [max_string_length] bytes
      holds any value. Raises if the text does not fit. *)
  val blit_to_bytes : t -> Bytes.t -> pos:int -> int
  [@@zero_alloc]

  (** [of_float f] rounds [f * 10^8] to the nearest unit. Binary floats rarely hold a
      decimal exactly, so the result can differ from the decimal the float was printed
      from, and halfway cases are not rounded symmetrically. [-0.0] gives [zero]. Raises
      [Invalid_argument] if [f] is NaN, infinite or outside the range. Prefer [of_string]
      for wire values; silence the alert with [[@alert "-lossy"]] where a float input is
      intended. *)
  val of_float : float -> t
  [@@alert
    lossy
      "Fixed_decimal.of_float rounds binary floats and raises on NaN, infinity or out of \
       range input; prefer of_string."]

  (** The float nearest to [t] while [abs (to_units t) <= 2^53] (about 9 * 10^7 whole
      units); beyond that the result can be one rounding further off. *)
  val to_float : t -> float

  (** Addition. Like [int] addition it wraps around on overflow instead of raising. *)
  val ( + ) : t -> t -> t
  [@@zero_alloc]

  (** Subtraction; wraps around on overflow. *)
  val ( - ) : t -> t -> t [@@zero_alloc]

  (** Negation. *)
  val neg : t -> t [@@zero_alloc]

  (** Absolute value. *)
  val abs : t -> t [@@zero_alloc]

  (** [scale t ~by] is [t * by] for a whole number [by]; wraps around on overflow. *)
  val scale : t -> by:int -> t
  [@@zero_alloc]

  (** [mul a b] is [a * b], truncated toward zero. Does not overflow for any result in
      range. *)
  val mul : t -> t -> t
  [@@zero_alloc]

  (** [div a b] is [a / b], truncated toward zero.

      Raises if [b] is zero. *)
  val div : t -> t -> t
  [@@zero_alloc]

  (** [div_int t n] is [t / n], truncated toward zero.

      Raises if [n] is zero. *)
  val div_int : t -> int -> t
  [@@zero_alloc]

  (** The sum of a list ([zero] for the empty list); wraps around on overflow. *)
  val sum : t list -> t

  (** [t = zero]. *)
  val is_zero : t -> bool [@@zero_alloc]

  (** [t > zero]. *)
  val is_positive : t -> bool [@@zero_alloc]

  (** [t < zero]. *)
  val is_negative : t -> bool [@@zero_alloc]

  (** Truncates toward zero to [decimals] fractional digits, [0 <= decimals <= 8].

      Raises if [decimals] is outside [[0, 8]]. *)
  val round_down : t -> decimals:int -> t
  [@@zero_alloc]

  (** Rounds half away from zero to [decimals] fractional digits.

      Raises if [decimals] is outside [[0, 8]]. *)
  val round_nearest : t -> decimals:int -> t
  [@@zero_alloc]
end

(** [Make ()] is a fresh fixed-point type. The functor is generative: two applications
    give incompatible types with the same representation, so a price cannot be passed
    where a size is expected. *)
module Make () : S

(** {2 Unit arithmetic}

    Every [S] instance counts units of [10^-8], so products and quotients can be computed
    on the raw units. The helpers below are what [S.mul] and [S.div] use; they are exposed
    for mixing distinct instances. *)

(** [mul_units a b] is [a * b / 10^8], truncated toward zero. Partial products are split
    so that no intermediate value overflows when the result fits in an [int]. *)
val mul_units : int -> int -> int
[@@zero_alloc]

(** [div_units a b] is [a * 10^8 / b], truncated toward zero, computed by long division so
    that no intermediate value overflows.

    Raises if [b = 0]. *)
val div_units : int -> int -> int
[@@zero_alloc]

(** Products and quotients across three instances, e.g. [Product (Price) (Size) (Usd)] for
    notional values. *)
module Product (A : S) (B : S) (C : S) : sig
  (** [mul a b] is [a * b] as a [C.t], truncated toward zero. *)
  val mul : A.t -> B.t -> C.t
  [@@zero_alloc]

  (** [div c b] is [c / b] as an [A.t], truncated toward zero.

      Raises if [b] is zero. *)
  val div : C.t -> B.t -> A.t
  [@@zero_alloc]
end

(** The original parser and printer, built from string splitting and [sprintf]. Kept as
    the reference the single-pass versions are tested against; not for hot paths. *)
module Reference : sig
  (** Units of a decimal string, [None] when [S.of_string] would raise. *)
  val units_of_string : string -> int option

  (** The decimal string of a unit count, as [S.to_string] prints it. *)
  val units_to_string : int -> string
end
