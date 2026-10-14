(* The worked example from the top of [fixed_decimal.mli]: three distinct decimal types
   and the notional value of a fill. *)

open! Core
module Price = Fixed_decimal.Make ()
module Size = Fixed_decimal.Make ()
module Usd = Fixed_decimal.Make ()
module Notional = Fixed_decimal.Product (Price) (Size) (Usd)

let () =
  let price = Price.of_string "113377.5"
  and size = Size.of_string "0.00123" in
  let notional = Notional.mul price size in
  printf "notional %s\n" (Usd.to_string notional);
  printf "price back %s\n" (Price.to_string (Notional.div notional size));
  printf "price rounded %s\n" (Price.to_string (Price.round_nearest price ~decimals:0));
  printf "fee 0.025%% %s\n" (Usd.to_string (Usd.mul notional (Usd.of_string "0.00025")))
;;
