(* Must not compile: distinct [Make ()] instances are distinct types. *)

module Price = Fixed_decimal.Make ()
module Size = Fixed_decimal.Make ()

let size_only (s : Size.t) = s
let _ = size_only (Price.of_int 1)
