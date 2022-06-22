(numericals.common:compiler-in-package numericals.common:*compiler-package*)

(5am:in-suite nu::array)

;;; FIXME: Optimize this: Within a factor of 2-3 of numpy for large arrays
;;; TODO: Better optimization notes

(define-polymorphic-function one-arg-reduce-fn (name initial-value-name x &key axes out) :overwrite t)

(defpolymorph (one-arg-reduce-fn :inline t) ((name symbol) (initial-value-name symbol)
                                             (x list) &key ((axes (not null))) ((out (not null))))
    t
  (one-arg-reduce-fn name initial-value-name (nu:asarray x) :axes axes :out out))

(defpolymorph (one-arg-reduce-fn :inline t) ((name symbol) (initial-value-name symbol)
                                             (x list) &key ((axes (not null))) ((out null)))
    t
  (declare (ignore out))
  (one-arg-reduce-fn name initial-value-name (nu:asarray x) :axes axes))

(defpolymorph (one-arg-reduce-fn :inline t) ((name symbol) (initial-value-name symbol)
                                             (x list) &key ((axes null)) ((out (not null))))
    t
  (declare (ignore axes))
  (one-arg-reduce-fn name initial-value-name (nu:asarray x) :out out))

(defpolymorph (one-arg-reduce-fn :inline t) ((name symbol) (initial-value-name symbol)
                                             (x list) &key ((axes null)) ((out null)))
    t
  (declare (ignore out axes))
  (one-arg-reduce-fn name initial-value-name (nu:asarray x)))


(macrolet ((def (type c-type c-fn-retriever type-size)
             (declare (ignorable c-type))

             `(progn

                (defpolymorph one-arg-reduce-fn ((name symbol)
                                                 (initial-value-name symbol)
                                                 (x (array ,type))
                                                 &key ((axes null)) ((out null)))
                    ,type
                  (declare (ignore axes out)
                           (ignorable name))
                  (let ((acc             (funcall initial-value-name ',type))
                        (cl-name         (cl-name name))
                        (,c-fn-retriever (,c-fn-retriever name)))
                    (declare (type real acc))
                    (ptr-iterate-but-inner (narray-dimensions x) n
                      ((ptr-x ,type-size inc-x x))
                      (setq acc (funcall cl-name
                                         acc
                                         (funcall ,c-fn-retriever n ptr-x inc-x))))
                    (if (typep acc ',type)
                        acc
                        (trivial-coerce:coerce acc ',type))))

                (defpolymorph (one-arg-reduce-fn :inline t)
                    ((name symbol)
                     (initial-value-name symbol)
                     (x (simple-array ,type))
                     &key ((axes null)) ((out null)))
                    ,type
                  (declare (ignore axes out initial-value-name)
                           (ignorable name))
                  (let ((svx             (array-storage x))
                        (size            (array-total-size x)))
                    (declare (type (cl:simple-array ,type 1) svx)
                             (type size size))
                    (with-pointers-to-vectors-data ((ptr-x svx))
                      (funcall (,c-fn-retriever name) size ptr-x 1))))

                (defpolymorph (one-arg-reduce-fn :inline t)
                    ((name symbol)
                     (initial-value-name symbol)
                     (x (array ,type))
                     &key ((axes integer))
                     ((out (array ,type))
                      (nu:full (let ((dim (narray-dimensions x)))
                                  (append (subseq dim 0 axes)
                                          (nthcdr (+ 1 axes) dim)))
                               :type ',type
                               :value (funcall initial-value-name ',type))))
                    (or ,type (array ,type))
                  (assert (< axes (array-rank x)))
                  (let* ((rank (array-rank x))
                         (perm (loop :for i :below rank
                                     :collect (cond ((= i (1- rank))
                                                     axes)
                                                    ((= i axes)
                                                     (1- rank))
                                                    (t i))))
                         (out (transpose (reshape out (let ((dim (array-dimensions
                                                                  (the (array ,type) x))))
                                                        (setf (nth axes dim) 1)
                                                        dim))
                                         perm))
                         (x   (transpose x perm))
                         (c-fn (,c-fn-retriever name)))
                    (declare (type (array ,type) x out))
                    (ptr-iterate-but-inner (narray-dimensions x) n
                      ((ptr-x   ,type-size inc-x x)
                       (ptr-out ,type-size inc-out out))
                      (setf (cffi:mem-ref ptr-out ,c-type)
                            (funcall c-fn n ptr-x inc-x))))
                  (if (zerop (array-rank out))
                      (row-major-aref out 0)
                      out))

                (defpolymorph (one-arg-reduce-fn :inline t)
                    ((name symbol)
                     (initial-value-name symbol)
                     (x (simple-array ,type))
                     &key ((axes integer))
                     ((out (simple-array ,type))
                      (nu:full (let ((dim (narray-dimensions x)))
                                  (append (subseq dim 0 axes)
                                          (nthcdr (+ 1 axes) dim)))
                               :type ',type
                               :value (funcall initial-value-name ',type))))
                    (or ,type (array ,type))
                  (assert (< axes (array-rank x)))
                  (if (= 1 (array-rank x))
                      (one-arg-reduce-fn name initial-value-name
                                         (the (array ,type 1) x)
                                         :axes axes)
                      (let ((svx    (array-storage x))
                            (svo    (array-storage out))
                            (stride (array-stride x axes))
                            (outer-stride (if (zerop axes)
                                              (array-total-size x)
                                              (array-stride x (1- axes))))
                            (axis-size (array-dimension x axes))
                            (stride-step (apply #'* (subseq (narray-dimensions out) axes)))
                            (c-fn (,c-fn-retriever name)))
                        (declare (type (cl:simple-array ,type 1) svx svo)
                                 (type size stride outer-stride stride-step axis-size))
                        (with-pointers-to-vectors-data ((ptr-x svx))
                          (dotimes (i (array-total-size svo))
                            (setf (cl:row-major-aref svo i) (funcall c-fn axis-size ptr-x stride))
                            (cffi:incf-pointer ptr-x ,type-size)
                            (when (= 0 (the-size (rem (1+ i) stride-step)))
                              (cffi:incf-pointer ptr-x
                                  (the-size (* ,type-size (the-size (- outer-stride stride-step))))))))))
                  (if (zerop (array-rank out))
                      (row-major-aref out 0)
                      out))

                ;; FIXME: Better handle when OUT is supplied
                (defpolymorph (one-arg-reduce-fn :inline nil)
                    ((name symbol)
                     (initial-value-name symbol)
                     (x (array ,type))
                     &key ((axes list))
                     ((out null)))
                    (or ,type (array ,type))
                  (declare (ignore out))
                  ;; Repeatedly reduce an array across each axis in AXES
                  (loop :with out := x
                        :for axis :in (sort (copy-list axes) #'>)
                        :do (setq out (one-arg-reduce-fn name initial-value-name out :axes axis))
                        :finally (return out))))))

  (def single-float :float    single-float-c-name 4)
  (def double-float :double    double-float-c-name 8)
  (def (signed-byte 64) :int64 int64-c-name 8)
  (def (signed-byte 32) :int32 int32-c-name 4)
  (def (signed-byte 16) :int16 int16-c-name 2)
  (def (signed-byte 08) :int8 int8-c-name  1)
  (def (unsigned-byte 64) :uint64 uint64-c-name 8)
  (def (unsigned-byte 32) :uint32 uint32-c-name 4)
  (def (unsigned-byte 16) :uint16 uint16-c-name 2)
  (def (unsigned-byte 08) :uint8 uint8-c-name  1)
  ;; (def fixnum           fixnum-c-name 8)
  )

(macrolet ((def (name initial-value-name)
             `(progn
                (define-polymorphic-function ,name (x &key axes out) :overwrite t)
                (defpolymorph ,name (x &key ((axes (not null))) ((out (not null)))) t
                  (one-arg-reduce-fn ',name ',initial-value-name x :axes axes :out out))
                (defpolymorph ,name (x &key ((axes (not null))) ((out null))) t
                  (declare (ignore out))
                  (one-arg-reduce-fn ',name ',initial-value-name x :axes axes))
                (defpolymorph ,name (x &key ((axes null)) ((out (not null)))) t
                  (one-arg-reduce-fn ',name ',initial-value-name x :axes axes :out out))
                (defpolymorph ,name (x &key ((axes null)) ((out null))) t
                  (declare (ignore out))
                  (one-arg-reduce-fn ',name ',initial-value-name x :axes axes)))))
  (def nu:sum type-zero)
  (def nu:maximum type-min)
  (def nu:minimum type-max))

(5am:def-test nu:sum ()
  (flet ((float-close-p (x y)
           (or (= x y)
               (progn
                 ;; (print (list x y))
                 (< (/ (abs (- x y))
                       (+ (abs x) (abs y)))
                    0.01)))))
    (loop :for *array-element-type* :in `(single-float
                                          double-float
                                          (signed-byte 64)
                                          (signed-byte 32)
                                          (signed-byte 16)
                                          (signed-byte 08)
                                          (unsigned-byte 64)
                                          (unsigned-byte 32)
                                          (unsigned-byte 16)
                                          (unsigned-byte 08)
                                          ;; fixnum
                                          )
          :do
             (5am:is (= 06 (nu:sum (nu:asarray '(1 2 3)))))
             (5am:is (= 21 (nu:sum (nu:asarray '((1 2 3)
                                                 (4 5 6))))))
             (5am:is (array= (nu:asarray '(5 7 9))
                             (nu:sum (nu:asarray '((1 2 3)
                                                (4 5 6)))
                                     :axes 0
                                     :out (nu:zeros 3))))
             (5am:is (array= (nu:asarray '(6 15))
                             (nu:sum (nu:asarray '((1 2 3)
                                                (4 5 6)))
                                     :axes 1
                                     :out (nu:zeros 2))))
             (5am:is (array= (nu:asarray '((5 7 9)
                                           (7 9 11)))
                             (nu:sum (nu:asarray '(((1 2 3)
                                                    (4 5 6))
                                                   ((7 8 9)
                                                    (0 1 2))))
                                     :axes 1
                                     :out (nu:zeros 2 3))))
             (5am:is (array= (nu:asarray '((6 15)
                                           (24 3)))
                             (nu:sum (nu:asarray '(((1 2 3)
                                                    (4 5 6))
                                                   ((7 8 9)
                                                    (0 1 2))))
                                     :axes 2
                                     :out (nu:zeros 2 2))))
             (5am:is (array= (nu:asarray '(30 18))
                             (nu:sum (nu:asarray '(((1 2 3)
                                                    (4 5 6))
                                                   ((7 8 9)
                                                    (0 1 2))))
                                     :axes '(0 2))))

             (let ((array (nu:rand 100)))
               (5am:is (float-close-p (nu:sum array)
                                      (let ((sum 0))
                                        (nu:do-arrays ((x array))
                                          (incf sum x))
                                        sum)))))))

(5am:def-test nu:maximum ()
  (flet ((float-close-p (x y)
           (or (= x y)
               (progn
                 ;; (print (list x y))
                 (< (/ (abs (- x y))
                       (+ (abs x) (abs y)))
                    0.01)))))
    (loop :for *array-element-type* :in `(single-float
                                          double-float
                                          (signed-byte 64)
                                          (signed-byte 32)
                                          (signed-byte 16)
                                          (signed-byte 08)
                                          (unsigned-byte 64)
                                          (unsigned-byte 32)
                                          (unsigned-byte 16)
                                          (unsigned-byte 08)
                                          ;; fixnum
                                          )
          :do
             (5am:is (= 3 (nu:maximum (nu:asarray '(1 2 3)))))
             (5am:is (= 9 (nu:maximum (nu:asarray '((1 2 3)
                                                    (4 5 6)
                                                    (7 8 9))))))
             (5am:is (array= (nu:asarray '(4 5 6))
                             (nu:maximum (nu:asarray '((1 2 3)
                                                       (4 5 6)))
                                         :axes 0
                                         :out (nu:zeros 3))))
             (5am:is (array= (nu:asarray '(3 6))
                             (nu:maximum (nu:asarray '((1 2 3)
                                                       (4 5 6)))
                                         :axes 1
                                         :out (nu:zeros 2))))
             (5am:is (array= (nu:asarray '((4 5 6)
                                           (7 8 9)))
                             (nu:maximum (nu:asarray '(((1 2 3)
                                                        (4 5 6))
                                                       ((7 8 9)
                                                        (0 1 2))))
                                         :axes 1
                                         :out (nu:zeros 2 3))))
             (5am:is (array= (nu:asarray '((3 6)
                                           (9 2)))
                             (nu:maximum (nu:asarray '(((1 2 3)
                                                        (4 5 6))
                                                       ((7 8 9)
                                                        (0 1 2))))
                                         :axes 2
                                         :out (nu:zeros 2 2))))
             (5am:is (array= (nu:asarray '(9 6))
                             (nu:maximum (nu:asarray '(((1 2 3)
                                                        (4 5 6))
                                                       ((7 8 9)
                                                        (0 1 2))))
                                     :axes '(0 2))))

             (let ((array (nu:rand 100)))
               (5am:is (float-close-p (nu:maximum array)
                                      (let ((max most-negative-double-float))
                                        (nu:do-arrays ((x array))
                                          (if (> x max) (setq max x)))
                                        max)))))))

(5am:def-test nu:minimum ()
  (flet ((float-close-p (x y)
           (or (= x y)
               (progn
                 ;; (print (list x y))
                 (< (/ (abs (- x y))
                       (+ (abs x) (abs y)))
                    0.01)))))
    (loop :for *array-element-type* :in `(single-float
                                          double-float
                                          (signed-byte 64)
                                          (signed-byte 32)
                                          (signed-byte 16)
                                          (signed-byte 08)
                                          (unsigned-byte 64)
                                          (unsigned-byte 32)
                                          (unsigned-byte 16)
                                          (unsigned-byte 08)
                                          ;; fixnum
                                          )
          :do
             (5am:is (= 1 (nu:minimum (nu:asarray '(1 2 3)))))
             (5am:is (= 1 (nu:minimum (nu:asarray '((1 2 3)
                                                    (4 5 6))))))
             (5am:is (array= (nu:asarray '(1 2 3))
                             (nu:minimum (nu:asarray '((1 2 3)
                                                       (4 5 6)))
                                         :axes 0
                                         :out (nu:zeros 3))))
             (5am:is (array= (nu:asarray '(1 4))
                             (nu:minimum (nu:asarray '((1 2 3)
                                                       (4 5 6)))
                                         :axes 1
                                         :out (nu:zeros 2))))
             (5am:is (array= (nu:asarray '((1 2 3)
                                           (0 1 2)))
                             (nu:minimum (nu:asarray '(((1 2 3)
                                                        (4 5 6))
                                                       ((7 8 9)
                                                        (0 1 2))))
                                         :axes 1
                                         :out (nu:zeros 2 3))))
             (5am:is (array= (nu:asarray '((1 4)
                                           (7 0)))
                             (nu:minimum (nu:asarray '(((1 2 3)
                                                        (4 5 6))
                                                       ((7 8 9)
                                                        (0 1 2))))
                                         :axes 2
                                         :out (nu:zeros 2 2))))
             (5am:is (array= (nu:asarray '(1 0))
                             (nu:minimum (nu:asarray '(((1 2 3)
                                                        (4 5 6))
                                                       ((7 8 9)
                                                        (0 1 2))))
                                     :axes '(0 2))))

             (let ((array (nu:rand 100)))
               (5am:is (float-close-p (nu:minimum array)
                                      (let ((min most-positive-double-float))
                                        (nu:do-arrays ((x array))
                                          (if (< x min) (setq min x)))
                                        min)))))))

;; ;;; The perf diff between simple and non-simple versions is less than 5%
;; ;;; for (RAND 1000 1000); may be we could delete this (?)
;; (defpolymorph nu:sum ((x (simple-array single-float))
;;                       &key ((axes null)) ((out null)))
;;     single-float
;;   (declare (ignore axes out))
;;   (cffi:with-foreign-pointer (ones 4)
;;     (setf (cffi:mem-aref ones :float) 1.0f0)
;;     (cblas:sdot (array-total-size x)
;;                          (ptr x) 1
;;                          ones 0)))

