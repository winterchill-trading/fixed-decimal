(lang dune 3.17)

(name fixed-decimal)

(generate_opam_files true)

(license MIT)

(authors "WinterChill AI")

(maintainers "hello@winterchill.xyz")

(source
 (github winterchill-trading/fixed-decimal))

(homepage "https://github.com/winterchill-trading/fixed-decimal")

(bug_reports "https://github.com/winterchill-trading/fixed-decimal/issues")

(documentation "https://github.com/winterchill-trading/fixed-decimal#readme")

(package
 (name fixed-decimal)
 (synopsis "Exact fixed-point decimals with 8 fractional digits, stored as an int")
 (description
  "Fixed_decimal represents a decimal number as an immediate int counting units of 10^-8, so addition, comparison and hashing are plain integer operations and never allocate. A generative functor gives each quantity (a price, a size, an amount) its own incompatible type. Multiplication and division are exact up to truncation and never overflow for an in-range result. Decimal strings parse and print in one pass without allocating, and the hot paths carry [@@zero_alloc]. Requires the OxCaml compiler.")
 (tags
  (decimal fixed-point money finance oxcaml))
 (depends
  oxcaml
  (ocaml
   (and
    (>= 5.2.0)
    (< 5.3~)))
  dune
  (core
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (ppx_jane
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (ppx_yojson_conv
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (ppx_yojson_conv_lib
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (yojson
   (>= 2.0.0))
  (zarith
   (and
    :with-test
    (>= 1.12)))
  (core_bench
   (and
    :with-test
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (core_unix
   (and
    :with-test
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (odoc :with-doc)))
