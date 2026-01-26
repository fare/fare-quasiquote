#+xcvb (module (:depends-on ("packages")))

(uiop:define-package :fare-quasiquote/test
  (:mix :fare-quasiquote :hu.dwim.stefil :common-lisp :trivia)
  (:shadowing-import-from :fare-quasiquote
   #:quasiquote #:unquote #:unquote-splicing #:unquote-nsplicing
   #:list #:append #:nconc #:list* #:cons #:quote #:vector
   #:kwote #:quotep #:n-vector #:make-vector
   #:quasiquote-expand #:quasiquote-expand-0 #:quasiquote-expand-1 #:expand-unquote
   #:quasiquote-unexpand #:quasiquote-unexpand-0 #:quasiquote-unexpand-1 #:quasiquote-unexpand-2))

(in-package :fare-quasiquote/test)

(defsuite* (fare-quasiquote-test :in root-suite :documentation "All fare-quasiquote tests"))

;; This version of princ allows one to see
;; inside of your implementation's version of quasiquoted expressions...

(defun rprinc (x)
  "hand-made princ that allows to see inside quasiquotes
(results are implementation-dependent)"
  (labels
      ((rprinc-list (x)
         (princ "(")
	 (rprinc-list-contents x)
	 (princ ")"))
       (rprinc-list-contents (x)
         (rprinc (car x))
	 (rprinc-cdr (cdr x)))
       (rprinc-cdr (x)
         (if x (if (consp x)
		   (progn
		     (princ " ")
		     (rprinc-list-contents x))
		 (progn
		   (princ " . ")
		   (rprinc x))))))
    (cond
     ((consp x) (rprinc-list x))
     (t (princ x)))
    x))

;; You can test the quasiquote implementation like this:

(defmacro with-qq-syntax ((&key) &body body)
  `(call-with-qq-syntax #'(lambda () ,@body)))
(defun call-with-qq-syntax (thunk)
  (with-standard-io-syntax
    (let ((*package* (find-package :fare-quasiquote/test))
          (*readtable* *fq-readtable*)
          (*print-pprint-dispatch* *fq-pprint-dispatch*)
          (*print-pretty* t)
          (*print-readably* nil)
          (*print-case* :downcase))
      (funcall thunk))))

(defun rq (s) (with-qq-syntax () (read-from-string s)))
(defun pq (x) (with-qq-syntax () (write-to-string x)))
(defun prq (x) (with-qq-syntax () (write-to-string (read-from-string x))))
(defun qq (x) (let* ((y (rq x)) (v (eval y)) (z (pq y)))
                `(q ,x ,y ,v ,@(unless (equal x z) (list z)))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *letter-feature*
    '((#\r (:not :quasiquote-at-macro-expansion-time))
      (#\m :quasiquote-at-macro-expansion-time)
      (#\q (:not :quasiquote-passes-literals))
      (#\l :quasiquote-passes-literals)
      (#\a (:not :quasiquote-strict-append))
      (#\s :quasiquote-strict-append)))

  (defun f? (x)
    (or (eq x t)
        (loop :for c :across (string-downcase x)
              :for f = (cadr (assoc c *letter-feature*))
              :always (uiop:featurep f))))

  (defun u (x)
    (match x
      ((list 't v) v)
      ((type cl:cons)
       (loop :for (f v) :in x :when (f? f) :return v))
      (otherwise x))))

(defmacro q (x y v &optional (z x))
  `(progn
     (is (equalp (rq ,(u x)) ',(u y)))
     (is (equalp ,(u y) ',(u v)))
     (is (equal (prq ,x) ',(or (u z) (u x))))))

(defmacro qx (&rest tests)
  `(progn
     ,@(loop :for (x y v z) :in tests
             :collect `(q ,x ,y ,v ,z))))

;;; Test values
(defparameter a '(vector 0))
(defparameter b 11)
(defparameter c (list 22 33))
(defparameter d (list 44 55))
(defmacro q-if-match (pat val then &optional else) ;; avoid pprint rules for if* on SBCL
  `(if-match ,pat ,val ,then ,else))
(defparameter *k '((cl:list :x x) (cl:list :y y)))

(deftest test-quasiquote ()
  (qx
   ("`a"
    ((r (quote a)) (m (quasiquote a)))
    (t a))
   ("``a"
    ((r (quote (quote a)))
     (m (quasiquote (quasiquote a))))
    (t (quote a)))
   ("`(a ,b)"
    ((r (list (quote a) b))
     (m (quasiquote (a (unquote b)))))
    (t (a 11)))
   ("``(a ,b)"
    ((r (quote (list (quote a) b)))
     (m (quasiquote (quasiquote (a (unquote b))))))
    (t (list (quote a) b)))
   ("`(a ,@c)"
    ((ra (cons (quote a) c))
     (rs (cons (quote a) (append c nil)))
     (m (quasiquote (a (unquote-splicing c)))))
    (t (a 22 33)))
   ("`(,@c)"
    ((ra c)
     (rs (append c nil))
     (m (quasiquote ((unquote-splicing c)))))
    (t (22 33))
    ((a "c")))
   ("`,`a"
    ((r (quote a))
     (m (quasiquote (unquote (quasiquote a)))))
    (t a)
    (t "`a"))
   ("`(a . ,b)"
    ((r (cons (quote a) b))
     (m (quasiquote (a unquote b))))
    (t (a . 11))
    ((a "`(a ,@b)")))
   ("`(a ,b ,@c)"
    ((ra (list* (quote a) b c))
     (rs (list* (quote a) b (append c nil)))
     (m (quasiquote (a (unquote b) (unquote-splicing c)))))
    (t (a 11 22 33)))
   ("(q-if-match `(a ,x . ,y) '(a b c d) (vector x y))"
    ((r (q-if-match (list* (quote a) x y) '(a b c d) (vector x y)))
     (m (q-if-match (quasiquote (a (unquote x) unquote y)) '(a b c d) (vector x y))))
    #(b (c d))
    ((a "(q-if-match `(a ,x ,@y) '(a b c d) (vector x y))")))
   ;; Unlike optima, trivia cannot match make-vector. TODO: enhance trivia to support make-vector
#|   ("(q-if-match `#(a ,x . ,y) #(a b c d) (vector x y))"
    ((r (q-if-match (make-vector (list* (quote a) x y)) #(a b c d) (vector x y)))
     (m (q-if-match (quasiquote (unquote (make-vector (list* (quote a) x y)))) #(a b c d) (vector x y))))
    #(b (c d))
    ((a "(q-if-match `#(a ,x ,@y) #(a b c d) (vector x y))")))
   ("(q-if-match `#(a ,x ,y d) #(a b c d) (vector x y))"
    ((r (q-if-match (make-vector (list (quote a) x y (quote d))) #(a b c d) (vector x y)))
     (m (q-if-match (quasiquote (unquote (make-vector (list (quote a) x y (quote d)))))
                    #(a b c d) (vector x y))))
    #(b c))|#
   ("`(1 2 3)"
    ((r (quote (1 2 3)))
     (m (quasiquote (1 2 3))))
    (t (1 2 3)))
   ("`(a ,@c . 4)"
    ((r (cons (quote a) (append c (quote 4))))
     (m (quasiquote (a (unquote-splicing c) . 4))))
    (t (a 22 33 . 4)))
   ("`(a ,b ,@c . ,d)"
    ((r (list* (quote a) b (append c d)))
     (m (quasiquote (a (unquote b) (unquote-splicing c) unquote d))))
    (t (a 11 22 33 44 55))
    ((a "`(a ,b ,@c ,@d)")))
   ("`(,@c . ,d)"
    ((r (append c d))
     (m (quasiquote ((unquote-splicing c) unquote d))))
    (t (22 33 44 55))
    ((a "`(,@c ,@d)")))
   ("```(,,a ,',',b)"
    ;; The pretty-printer in 0.9.0 and earlier, had a bug inherited from SBCL,
    ;; and couldn't pretty-print this form back to its value.
    ((r (list (quote list) (quote (quote list)) (quote a)
              (list (quote list) (quote (quote common-lisp:quote)) (list (quote common-lisp:quote) b))))
     (m (quasiquote (quasiquote (quasiquote ((unquote (unquote a)) (unquote '(unquote '(unquote b)))))))))
    (t (list (quote list) a (list (quote common-lisp:quote) '11))))
   ("`#(a ,b)"
    ((r (make-vector (list (quote a) b)))
     (m (quasiquote (unquote (make-vector (list (quote a) b))))))
    #(a 11))
   ("`#3(a ,b)"
    ((r (n-vector 3 (list (quote a) b)))
     (m (quasiquote (unquote (n-vector 3 (list (quote a) b))))))
    #(a 11 11))
   ("`#5(a ,@c)"
    ((rs (n-vector 5 (cons (quote a) (append c nil))))
     (ra (n-vector 5 (cons (quote a) c)))
     (ms (quasiquote (unquote (n-vector 5 (cons (quote a) (append c nil))))))
     (ma (quasiquote (unquote (n-vector 5 (cons (quote a) c))))))
    #(a 22 33 33 33))
   ("`(foobar a b ,c ,'(e f g) d ,@'(e f g) (h i j) ,@c)"
    ((rs (list* (quote foobar) (quote a) (quote b) c '(e f g) (quote d)
                (append '(e f g) (cons (quote (h i j)) (append c nil)))))
     (ra (list* (quote foobar) (quote a) (quote b) c '(e f g) (quote d)
                (append '(e f g) (cons (quote (h i j)) c))))
     (m (quasiquote (foobar a b (unquote c) (unquote '(e f g)) d
                            (unquote-splicing '(e f g)) (h i j) (unquote-splicing c)))))
    (t (foobar a b (22 33) (e f g) d e f g (h i j) 22 33)))
   ("``(, @c)"
    ((r (quote (list @c)))
     (m (quasiquote (quasiquote ((unquote @c))))))
    (t (list @c)))
   ("``(, .c)"
    ((r (quote (list .c)))
     (m (quasiquote (quasiquote ((unquote .c))))))
    (t (list .c)))
   ("`(1 ,b)"
    ((rq (list (quote 1) b))
     (rl (list 1 b))
     (m (quasiquote (1 (unquote b)))))
    (t (1 11)))
   ;; From the SBCL test suite
   ("(list 'foo b)" (t (list 'foo b)) (t (foo 11)) "`(,'foo ,b)"))
  (let ((c (list 2 3)))
    (q "`(x ,b ,@a ,.c ,.d)"
       ((ra (list* (quote x) b (append a (nconc c d))))
        (rs (list* (quote x) b (append a (nconc c d nil))))
        (m (quasiquote (x (unquote b) (unquote-splicing a) (unquote-nsplicing c) (unquote-nsplicing d)))))
       (t (x 11 vector 0 2 3 44 55))
       ((a "`(x ,b ,@a ,.c ,@d)")))
    ;; NCONC is evil. Use at your own risk!
    (is (equal c '(2 3 44 55))))
  (signals error (rq "`(foo bar #.(max 5 ,*print-base*))"))
  ;; From the exscribe tests
  (is (equal (pq (eval (rq "``(f ,@,@*k)"))) "`(f ,@(common-lisp:list :x x) ,@(common-lisp:list :y y))"))
  ;; From James M. Lawrence <llmjjmll@gmail.com>
  (loop for x in '("(x)" "`(,x)" "``(,,x)" "```(,,,x)") do
    (is (equal (prq x) x)))
  (is (equal (prq "`#.#(1 2 3)") "`#(1 2 3)")) ;; #. must reset the quasiquote level.
  (signals error (rq "`(foo bar #.(max 5 ,*print-base*))"))
  t)

;;; Double-quasiquote test from the SBCL test suite backq.impure.lisp
(defparameter *qq* '(*rr* *ss*))
(defparameter *rr* '(3 5))
(defparameter *ss* '(4 6))
(defun *rr* (x) (reduce #'* x))
(defparameter *x* '(a b))
(defparameter *y* '(c))
(defparameter *p* '(append *x* *y*))
(defparameter *q* '((append *x* *y*) (list 'sqrt 9)))
(defparameter *r* '(append *x* *y*))
(defparameter *s* '((append *x* *y*)))

(defparameter *double-quasiquote-tests*
  '(("``(,,*qq*)" . (24))
    ;;("``(,@,*qq*)" . 24) Invalid
    ("``(,,@*qq*)" . ((3 5) (4 6)))
    ("``(foo ,,*p*)" . (foo (a b c)))
    ;;("``(foo ,,@*q*)" . (foo (a b c) (sqrt 9)))
    ("``(foo ,',*r*)" . (foo (append *x* *y*)))
    ("``(foo ,',@*s*)" . (foo (append *x* *y*)))
    ("``(foo ,@,*p*)" . (foo a b c))
    ("``(foo ,@',*r*)" . (foo append *x* *y*))
    ;; the following expression produces different result under LW.
    ;;("``(foo . ,,@*q*)" . (foo a b c sqrt 9))
    ;; these three did not work.
    ("``(foo ,@',@*s*)" . (foo append *x* *y*))
    ("``(foo ,@,@*q*)" . (foo a b c sqrt 9))
    ("``(,@,@*qq*)" . (3 5 4 6))
    ("``(,,@(list 1 2 3) 10)" . (1 2 3 10))))

(deftest test-double-quasiquote ()
  (loop :for (expression . value) :in *double-quasiquote-tests* :do
    (is (equal (eval (eval (rq expression))) value)))
  t)

;;; This test is from dougk's 2014 patch to sbcl's backquote
#-(or quasiquote-strict-append quasiquote-passes-literals quasiquote-at-macro-expansion-time)
(deftest test-nested-backquote-readable-bogosity ()
  (eval (rq "(defmacro broken-macro (more-bindings)
                `(macrolet ((with-bindings (&body body)
                    `(let ((thing1 :something) ,',@more-bindings) ,@body)))
                   (with-bindings (thing))))"))
  (flet ((e (s x)
           (eval `(is (equalp (rq ,s) (macroexpand-1 ',x))))))
    ;; this example's expansion is correct but only by accident
    (e "(macrolet ((with-bindings (&body body)
           `(let ((thing1 :something) ,'(var val)) ,@body)))
          (with-bindings (thing)))"
       '(broken-macro ((var val))))
    ;; this example shows that we correctly display an invalid
    ;; QUOTE special-form that has no operand
    (e "(macrolet ((with-bindings (&body body)
           `(let ((thing1 :something) ,(cl:quote)) ,@body)))
          (with-bindings (thing)))"
       '(broken-macro nil))
    ;; ... or two operands
    (e "(macrolet ((with-bindings (&body body)
           `(let ((thing1 :something) ,(cl:quote (var :some-form) (var2 2))) ,@body)))
          (with-bindings (thing)))"
       '(broken-macro ((var :some-form) (var2 2))))
    ;; ... or an attempt to bind the symbol nil
    (e "(macrolet ((with-bindings (&body body)
           `(let ((thing1 :something) ,'nil) ,@body)))
          (with-bindings (thing)))"
       '(broken-macro (nil)))
    ;; ... or even a meaningless dotted-list quote form
    (e "(macrolet ((with-bindings (&body body)
           `(let ((thing1 :something) ,(cl:quote . frob)) ,@body)))
          (with-bindings (thing)))"
       '(broken-macro frob))))

(deftest preserving-inner-backquotes ()
  (flet ((e (s v)
           (eval `(is (equal (pq (eval (rq ,v))) ,s)))))

    ;; Continuing with *BACKQUOTE-TESTS*, instead of checking for the value
    ;; after twice evaluating, check for expected printed form after one eval.
    (e "`(,(*rr* *ss*))" "``(,,*qq*)")
    #+quasiquote-strict-append
    (e "`(,@(*rr* *ss*))" "``(,@,*qq*))")
    #-quasiquote-strict-append
    (e "(*rr* *ss*)" "``(,@,*qq*))")
    (e "`(,*rr* ,*ss*)" "``(,,@*qq*)")
    ;; could do the rest but pprinting is pretty simple now, so ... nah

    ;; Three tests inspired by tests from CLISP, but our answers are, I think,
    ;; better because we preserve inner quasiquotation. This is permissible
    ;; since a backquoted expression containing #\` nested to depth N has
    ;; no concrete form expressible as literals until N evaluations.
    ;; This is made clear if not in the normative part of CLHS,
    ;; then certainly in the appendix to CLtL2.

    (defvar x '(a b c))

    (e "(foo `(bar ,@'((baz 'a a) (baz 'b b) (baz 'c c) (baz 'd d))))"
       "(let ((list '(a b c d)))
         `(foo `(bar ,@',(mapcar (lambda (sym) `(baz ',sym ,sym))
                                 list))))")
    (e "x" "````,,,,'x") ;; NB: SBCL preserves "```,,,x"

    ;; In this one the leftmost backquote's comma is the second from the left.
    ;; That subform is "`,3" which is just 3. The inner quasiquote remains.
    (e "3" "``,,`,3"))) ;; NB: SBCL preserves "`,3"

#| ;; We fail these tests that SBCL is proud of passing.
(deftest preserving-backquotes-difficult ()
  (is (equal (prq "(let ((c 'cee) (d 'dee) (g 'gee) (h 'hooray))
                       `(`(a ,b ,',c ,,d) . `(e ,f ,',g ,,h))))")
             "(`(a ,b ,'cee ,dee) . `(e ,f ,'gee ,hooray))"))
  (is (equal (prq "(let ((c 'cee) (d 'dee) (g 'gee) (h 'hooray))
                       `(foo `(a ,b ,',c ,,d) . `(e ,f ,',g ,,h))))")
             "(foo `(a ,b ,'cee ,dee) . `(e ,f ,'gee ,hooray))"))) |#

(deftest pprint-backquote-magic ()
  (is (equal (prq "`(,  .foo)") "`(, .foo)"))
  (is (equal (prq "`(,  @foo)") "`(, @foo)"))
  (is (equal (prq "`(,  ?foo)") "`(,?foo)"))
  (is (equal (prq "`(x .,  @foo)")
             #-quasiquote-strict-append "`(x ,@@foo)"
             #+quasiquote-strict-append "`(x . , @foo)")))

;;; unquoted lambda lists should not leak the UNQUOTE implementation.
(deftest pprint-leaking-backq-comma ()
  (is (equal (prq "`(foo ,x)") "`(foo ,x)"))
  (is (equal (prq "`(foo ,@x)") "`(foo ,@x)"))
  (is (equal (prq "`(foo ,.x)")
             #-quasiquote-strict-append "`(foo ,@x)"
             #+quasiquote-strict-append "`(foo ,.x)"))
  (is (equal (prq "`(foo (,x))") "`(foo (,x))")))

;;;; One more test from the SBCL test suite:
;;; more backquote printing brokenness, fixed quasi-randomly by CSR.
;;; NOTE KLUDGE FIXME: because our backquote optimizes at read-time,
;;; these assertions, like the ones above, are fragile.  Likewise, it
;;; is very possible that at some point READABLY printing backquote
;;; expressions will have to change to printing the low-level conses,
;;; since the magical symbols are accessible though (car '`(,foo)) and
;;; friends.  HATE HATE HATE.  -- CSR, 2004-06-10
(deftest pprint-more-backquote-brokenness ()
  (flet ((e (input)
           (is (equalp input (prq input)))))
    (map () #'e
         '("``(foo ,@',@bar)"
           "``(,,foo ,',foo foo)"
           "``(((,,foo) ,',foo) foo)"
           "`#()"
           "`#(,bar)"
           "`#(,(bar))"
           ;; "`#(,@bar)" ; invalid
           "`#(,@(bar))"
           "`#(a ,b c)"
           #+quasiquote-strict-append "`#(a ,b . ,c)"
           "`#(,@a ,b c)"
           #+quasiquote-strict-append
           "`(,a . #(foo #() #(,bar) ,bar))"
           "(xlet ((foo (x))) `(xlet (,foo) (xsetq ,foo (y)) (baz ,foo)))"))))

#|
;; To test this system in all configurations:

cl-launch \
"(asdf:test-system :fare-quasiquote :force '(fare-quasiquote fare-quasiquote-test))"

cl-launch \
"(progn
   (pushnew :quasiquote-at-macro-expansion-time *features*)
   (asdf:test-system :fare-quasiquote :force '(fare-quasiquote fare-quasiquote-test)))"

cl-launch \
"(progn
   (pushnew :quasiquote-passes-literals *features*)
   (asdf:test-system :fare-quasiquote :force '(fare-quasiquote fare-quasiquote-test)))"

cl-launch \
"(progn
   (pushnew :quasiquote-at-macro-expansion-time *features*)
   (pushnew :quasiquote-passes-literals *features*)
   (asdf:test-system :fare-quasiquote :force '(fare-quasiquote fare-quasiquote-test)))"
|#
