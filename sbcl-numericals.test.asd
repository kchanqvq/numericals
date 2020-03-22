(asdf:defsystem "sbcl-numericals.test"
  :pathname "t/"
  :version "0.1.0"
  :serial t
  :depends-on ("sbcl-numericals"
               "fiveam"
               "alexandria")
  :components ((:file "package")
               (:file "avx-double")
               (:file "avx-single")
               (:file "sse-double")
               (:file "sse-single")))
