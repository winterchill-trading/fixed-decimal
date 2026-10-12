(lang dune 3.17)
(name fixed-decimal)
(generate_opam_files true)
(license MIT)
(source (github winterchill-trading/fixed-decimal))
(package
 (name fixed-decimal)
 (synopsis "Fixed-point decimal numbers for trading systems")
 (depends
  (ocaml (>= 5.2))
  dune
  core
  ppx_jane
  ppx_yojson_conv
  yojson
  (zarith :with-test)))
