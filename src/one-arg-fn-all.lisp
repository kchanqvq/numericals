(numericals.common:compiler-in-package numericals.common:*compiler-package*)

(5am:in-suite nu::array)

(define-constant +one-arg-fn-all-doc+
  ;; See the below non-array polymorphs for the element-type deduction procedure
  "
These functions have a single array as input and a single array as output.
If the output array is not supplied, its element-type is computed :AUTO-matically

For large arrays, you should be happy without any declarations. You can
use *MULTITHREADED-THRESHOLD* to a large enough value to disable lparallel
based multithreading.

Declarations become necessary for smaller arrays. An (OPTIMIZE SPEED) declaration
should help you with optimization by providing optimization notes.
Optimization for small arrays essentially involves inlining, along with:
  (i)  providing the OUT parameter to allow the user to eliminate allocation wherever possible
  (ii) eliminating work involved in broadcasting and multithreading

TODO: Provide more details
  "
  :test #'string=)

(define-polymorphic-function one-arg-fn/all (name x &key out broadcast) :overwrite t
  :documentation +one-arg-fn-all-doc+)

(macrolet ((def (type c-type fn-retriever size)

             `(progn

                ;; most optimal case: BROADCAST is NIL and OUT is supplied
                (defpolymorph (one-arg-fn/all :inline t)
                    ((name symbol) (x (simple-array ,type))
                     &key ((out (simple-array ,type)))
                     ((broadcast null) nu:*broadcast-automatically*))
                    (simple-array ,type)
                  (declare (ignorable name broadcast))
                  (policy-cond:with-expectations (= safety 0)
                      ((assertion (or broadcast
                                      (equalp (narray-dimensions x)
                                              (narray-dimensions out)))))
                    (let ((svx (array-storage x))
                          (svo (array-storage out)))
                      (declare (type (cl:simple-array ,type 1) svx svo))
                      (with-thresholded-multithreading/cl
                          (cl:array-total-size svo)
                          (svx svo)
                        (with-pointers-to-vectors-data ((ptr-x (array-storage svx))
                                                        (ptr-o (array-storage svo)))
                          (cffi:incf-pointer ptr-x (* ,size (cl-array-offset svx)))
                          (cffi:incf-pointer ptr-o (* ,size (cl-array-offset svo)))
                          (funcall (,fn-retriever name)
                                   (array-total-size svo)
                                   ptr-x 1
                                   ptr-o 1)))))
                  out)

                ;; BROADCAST is NIL, but OUT is unsupplied
                (defpolymorph (one-arg-fn/all :inline t :suboptimal-note runtime-array-allocation)
                    ((name symbol) (x (simple-array ,type))
                     &key ((out null))
                     ((broadcast null) nu:*broadcast-automatically*))
                    (simple-array ,type)
                  (declare (ignorable name out broadcast))
                  (let ((out (nu:zeros (narray-dimensions x) :type ',type)))
                    (declare (type (array ,type) out))
                    (let ((svx (array-storage x))
                          (svo (array-storage out)))
                      (declare (type (cl:array ,type 1) svx svo))
                      (with-thresholded-multithreading/cl
                          (array-total-size svo)
                          (svx svo)
                        (with-pointers-to-vectors-data ((ptr-x (array-storage svx))
                                                        (ptr-o (array-storage svo)))
                          (cffi:incf-pointer ptr-x (* ,size (cl-array-offset svx)))
                          (cffi:incf-pointer ptr-o (* ,size (cl-array-offset svo)))
                          (funcall (single-float-c-name name)
                                   (array-total-size svo)
                                   ptr-x 1
                                   ptr-o 1))))
                    out))

                ;; OUT is unsupplied
                (defpolymorph (one-arg-fn/all :inline :maybe
                                              :suboptimal-note runtime-array-allocation)
                    ((name symbol) (x (array ,type))
                     &key ((out null))
                     (broadcast nu:*broadcast-automatically*))
                    (simple-array ,type)
                  (declare (ignorable name out broadcast))
                  (let ((out (nu:zeros-like x)))
                    (declare (type (array ,type) out))
                    (ptr-iterate-but-inner (narray-dimensions out) n
                      ((ptr-x   ,size ix   x)
                       (ptr-out ,size iout out))
                      (funcall (,fn-retriever name) n ptr-x ix ptr-out iout))
                    out))

                ;; OUT is supplied, but BROADCAST is not known to be NIL

                (defpolymorph (one-arg-fn/all
                               :inline :maybe
                               :more-optimal-type-list
                               (symbol (simple-array ,type)
                                       &key (:out (simple-array ,type))
                                       (:broadcast null)))
                    ((name symbol) (x (array ,type))
                     &key ((out (array ,type)))
                     (broadcast nu:*broadcast-automatically*))
                    (array ,type)
                  (if broadcast
                      (multiple-value-bind (broadcast-compatible-p broadcast-dimensions)
                          (%broadcast-compatible-p (narray-dimensions x)
                                                   (narray-dimensions out))
                        (assert broadcast-compatible-p (x out)
                                'incompatible-broadcast-dimensions
                                :dimensions (mapcar #'narray-dimensions (list x out))
                                :array-likes (list x out))
                        ;; It is possible for us to use multithreading along with broadcasting for
                        ;; DENSE-ARRAYS:ARRAY
                        (ptr-iterate-but-inner broadcast-dimensions n
                          ((ptr-x   ,size ix   x)
                           (ptr-out ,size iout out))
                          (funcall (,fn-retriever name) n ptr-x ix ptr-out iout)))
                      (policy-cond:with-expectations (= safety 0)
                          ((assertion (or broadcast
                                          (equalp (narray-dimensions x)
                                                  (narray-dimensions out)))))
                        (ptr-iterate-but-inner (narray-dimensions out) n
                          ((ptr-x   ,size ix   x)
                           (ptr-out ,size iout out))
                          (funcall (,fn-retriever name) n ptr-x ix ptr-out iout))))
                  out)

                ;; Direct NUMBER to ARRAY: BROADCAST is necessarily non-NIL
                (defpolymorph (one-arg-fn/all :inline t)
                    ((name symbol) (x real)
                     &key ((out (array ,type)))
                     ((broadcast (not null))))
                    (array ,type)
                  (declare (ignore broadcast))
                  (cffi:with-foreign-pointer (ptr-x ,size)
                    (setf (cffi:mem-ref ptr-x ,c-type)
                          (trivial-coerce:coerce x ',type))
                    (let ((svo (array-storage out)))
                      (declare (type (cl:simple-array ,type 1) svo))
                      (with-thresholded-multithreading/cl
                          (cl:array-total-size svo)
                          (svo)
                        (with-pointers-to-vectors-data ((ptr-o svo))
                          (funcall (,fn-retriever name)
                                   (array-total-size svo)
                                   ptr-x 0
                                   ptr-o 1)))))
                  out))))

  (def (signed-byte 64) :long  int64-c-name 8)
  (def (signed-byte 32) :int   int32-c-name 4)
  (def (signed-byte 16) :short int16-c-name 2)
  (def (signed-byte 08) :char  int8-c-name  1)

  (def (unsigned-byte 64) :unsigned-long  uint64-c-name 8)
  (def (unsigned-byte 32) :unsigned-int   uint32-c-name 4)
  (def (unsigned-byte 16) :unsigned-short uint16-c-name 2)
  (def (unsigned-byte 08) :unsigned-char  uint8-c-name  1)

  (def fixnum       :long   fixnum-c-name       8)
  (def single-float :float  single-float-c-name 4)
  (def double-float :double double-float-c-name 8))

;; pure number
(defpolymorph (one-arg-fn/all :inline t) ((name symbol) (x number)
                                          &key ((out null))
                                          (broadcast nu:*broadcast-automatically*))
    (values number &optional)
  (declare (ignorable out name broadcast))
  (funcall (cl-name name) x))

;; lists - 2 polymorphs
(defpolymorph (one-arg-fn/all :inline t :suboptimal-note runtime-array-allocation)
    ((name symbol) (x list)
     &key ((out null))
     (broadcast nu:*broadcast-automatically*))
    (values array &optional)
  (declare (ignorable out))
  ;; Why didn't we create ARRAY in the lambda-list itself?
  ;;   We can do, once NU:ZEROS-LIKE starts taking TYPE as an argument
  ;;   Also think over the implication of being required to allocate a separate
  ;; array in the second case below; perhaps we also need a way to copy from a
  ;; array-like to an array.
  (let ((array (nu:asarray x :type :auto)))
    (one-arg-fn/all name array :out array :broadcast broadcast)))

(defpolymorph (one-arg-fn/all :inline t :suboptimal-note runtime-array-allocation)
    ((name symbol) (x list)
     &key ((out array))
     (broadcast nu:*broadcast-automatically*))
    (values array &optional)
  (declare (ignorable out))
  ;; TODO: Define copy from list to array directly
  (one-arg-fn/all name (nu:asarray x :type (array-element-type out)) :out out :broadcast broadcast))

(macrolet ((def (name)
             `(progn
                (define-polymorphic-function ,name (x &key out broadcast)
                  :overwrite t :documentation +one-arg-fn-all-doc+)
                (defpolymorph ,name (x &key ((out null)) (broadcast nu:*broadcast-automatically*)) t
                  (declare (ignore out))
                  (one-arg-fn/all ',name x :broadcast broadcast))
                (defpolymorph ,name (x &key ((out (not null))) (broadcast nu:*broadcast-automatically*))
                    t
                  (one-arg-fn/all ',name x :out out :broadcast broadcast))
                (define-numericals-one-arg-test ,name nu::array (0.0f0) (0.0d0))
                (define-numericals-one-arg-test/integers ,name nu::array))))

  (def nu:abs))