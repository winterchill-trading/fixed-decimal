(** Fixed-point decimals backed by an [int] counting units of [10^-8].

    Decimal strings (e.g. ["113377.5"]) are the usual wire encoding for prices, sizes and
    amounts. Values parsed with more than 8 fractional digits are truncated toward zero.
    The range is roughly +/- 4.6e10. *)

open! Core

module type S = sig
  type t [@@deriving sexp, compare, equal, hash, yojson]

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
      input. *)
  val of_string : string -> t

  val of_string_opt : string -> t option

  (** Shortest decimal representation without trailing zeros, e.g. ["100"], ["0.001"],
      ["-12.5"]. *)
  val to_string : t -> string

  (** Rounds to the nearest unit. *)
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

  (** Truncates toward zero to [decimals] fractional digits, [0 <= decimals <= 8]. *)
  val round_down : t -> decimals:int -> t

  (** Rounds half away from zero to [decimals] fractional digits. *)
  val round_nearest : t -> decimals:int -> t
end

module Make () : S
