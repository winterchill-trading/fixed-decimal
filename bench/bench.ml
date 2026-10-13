open! Core
open Core_bench
module Price = Fixed_decimal.Make ()
module Size = Fixed_decimal.Make ()
module Usd = Fixed_decimal.Make ()
module Notional = Fixed_decimal.Product (Price) (Size) (Usd)

(* [Sys.opaque_identity] keeps the compiler from folding the operands into constants. *)
let px = Price.of_string "113377.5"
let sz = Size.of_string "0.00123"
let usd = Usd.of_string "139.454325"
let a = Price.of_string "1891.4"
let b = Price.of_string "0.25"
let px_string = "113377.5"
let sz_string = "0.00123"

let tests =
  [ Bench.Test.create ~name:"empty" (fun () -> ())
  ; Bench.Test.create ~name:"Int.( * ) baseline" (fun () ->
      ignore (Int.( * ) (Sys.opaque_identity 1891) (Sys.opaque_identity 25) : int))
  ; Bench.Test.create ~name:"mul" (fun () ->
      ignore (Price.mul (Sys.opaque_identity a) (Sys.opaque_identity b) : Price.t))
  ; Bench.Test.create ~name:"div" (fun () ->
      ignore (Price.div (Sys.opaque_identity a) (Sys.opaque_identity b) : Price.t))
  ; Bench.Test.create ~name:"Product.mul" (fun () ->
      ignore (Notional.mul (Sys.opaque_identity px) (Sys.opaque_identity sz) : Usd.t))
  ; Bench.Test.create ~name:"Product.div" (fun () ->
      ignore (Notional.div (Sys.opaque_identity usd) (Sys.opaque_identity sz) : Price.t))
  ; Bench.Test.create ~name:"of_string price" (fun () ->
      ignore (Price.of_string (Sys.opaque_identity px_string) : Price.t))
  ; Bench.Test.create ~name:"of_string size" (fun () ->
      ignore (Size.of_string (Sys.opaque_identity sz_string) : Size.t))
  ; Bench.Test.create ~name:"to_string price" (fun () ->
      ignore (Price.to_string (Sys.opaque_identity px) : string))
  ; Bench.Test.create ~name:"to_string size" (fun () ->
      ignore (Size.to_string (Sys.opaque_identity sz) : string))
  ]
;;

let () = Command_unix.run (Bench.make_command tests)
