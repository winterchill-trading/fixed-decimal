(** Fixed-point decimals backed by an [int] counting units of [10^-8].

    Decimal strings (e.g. ["113377.5"]) are the usual wire encoding for prices, sizes and
    amounts. Values parsed with more than 8 fractional digits are truncated toward zero.
    The range is +/- 46116860184.27387903 (the magnitude of [max_int] in units of 10^-8);
    larger values are rejected. *)

open! Core

module type S = sig
  (** A count of [10^-8] units. [t] is an immediate [int] at runtime: values are never
      boxed and arithmetic does not allocate. *)
  type t : immediate [@@deriving sexp, compare, equal, hash, yojson]

  include Comparable.S with type t := t

  (** Number of fractional decimal digits (8). *)
  val decimals : int

  (** Number of units in [one] (10^8). *)
  val units_per_one : int

  val zero : t
  val one : t
  val of_units : int -> t
  val to_units : t -> int
  val of_int : int -> t

  (** Parses a decimal string such as ["-12.5"], ["0.001"] or ["100"]. Raises on malformed
      input or on a value outside the range. *)
  val of_string : string -> t

  val of_string_opt : string -> t option

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

  val to_float : t -> float
  val ( + ) : t -> t -> t
  val ( - ) : t -> t -> t
  val neg : t -> t
  val abs : t -> t
  val scale : t -> by:int -> t

  (** [mul a b] is [a * b], truncated toward zero. Does not overflow for any result in
      range. *)
  val mul : t -> t -> t

  (** [div a b] is [a / b], truncated toward zero. Raises if [b] is zero. *)
  val div : t -> t -> t

  (** [div_int t n] is [t / n], truncated toward zero. Raises if [n] is zero. *)
  val div_int : t -> int -> t

  val sum : t list -> t
  val is_zero : t -> bool
  val is_positive : t -> bool
  val is_negative : t -> bool

  (** Truncates toward zero to [decimals] fractional digits, [0 <= decimals <= 8]. *)
  val round_down : t -> decimals:int -> t

  (** Rounds half away from zero to [decimals] fractional digits. *)
  val round_nearest : t -> decimals:int -> t
end

module Make () : S

(** {2 Unit arithmetic}

    Every [S] instance counts units of [10^-8], so products and quotients can be computed
    on the raw units. The helpers below are what [S.mul] and [S.div] use; they are exposed
    for mixing distinct instances. *)

(** [mul_units a b] is [a * b / 10^8], truncated toward zero. Partial products are split
    so that no intermediate value overflows when the result fits in an [int]. *)
val mul_units : int -> int -> int

(** [div_units a b] is [a * 10^8 / b], truncated toward zero, computed by long division so
    that no intermediate value overflows. Raises if [b = 0]. *)
val div_units : int -> int -> int

(** Products and quotients across three instances, e.g. [Product (Price) (Size) (Usd)] for
    notional values. *)
module Product (A : S) (B : S) (C : S) : sig
  (** [mul a b] is [a * b] as a [C.t], truncated toward zero. *)
  val mul : A.t -> B.t -> C.t

  (** [div c b] is [c / b] as an [A.t], truncated toward zero. Raises if [b] is zero. *)
  val div : C.t -> B.t -> A.t
end

(** The original parser and printer, built from string splitting and [sprintf]. Kept as
    the reference the single-pass versions are tested against; not for hot paths. *)
module Reference : sig
  (** Units of a decimal string, [None] when [S.of_string] would raise. *)
  val units_of_string : string -> int option

  val units_to_string : int -> string
end
