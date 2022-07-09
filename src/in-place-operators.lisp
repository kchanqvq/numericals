(numericals.common:compiler-in-package numericals.common:*compiler-package*)

(macrolet ((def (&rest names)
             `(progn
                ,@(loop :for name :in names
                        :for name! := (find-symbol (format nil "~A!" name) :nu)
                        :collect `(progn
                                    (define-polymorphic-function ,name! (x) :overwrite t)
                                    (defpolymorph (,name! :inline t) (x) t
                                      (,name x :out x :broadcast nil)))))))
  (def nu:sin nu:asin nu:sinh nu:asinh
       nu:cos nu:acos nu:cosh nu:acosh
       nu:tan         nu:tanh nu:atanh
    nu:exp nu:abs nu:fround nu:ftruncate nu:ffloor nu:fceiling))

(macrolet ((def (&rest names)
             `(progn
                ,@(loop :for name :in names
                        :for name! := (find-symbol (format nil "~A!" name) :nu)
                        :collect `(progn
                                    (define-polymorphic-function ,name! (x y &key broadcast)
                                      :overwrite t)
                                    (defpolymorph (,name! :inline t)
                                        (x y &key (broadcast nu:*broadcast-automatically*))
                                        t
                                      (,name x y :out x :broadcast broadcast)))))))
  (def nu:expt nu:add nu:subtract nu:multiply nu:divide))
