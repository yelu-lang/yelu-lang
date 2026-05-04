(lang dune 3.10)
(name yelu)
(generate_opam_files true)
(maintainers "Shiwei Weng <weng@cs.jhu.edu>")
(package
 (name yelu)
 (synopsis "programmable configuration shell language — cmake pack")
 (depends
  base fmt fix re
  ppx_jane
  (alcotest :with-test)))
(license MIT)
