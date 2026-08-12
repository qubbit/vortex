; Quasiquote and templating
; -------------------------
; Quasiquote (`) builds a list literally, except where unquote (,) drops in an
; evaluated value and unquote-splicing (,@) splices in the elements of a list.
; `when` and `unless` are one-armed conditionals.

(define name 'world)
(define numbers '(2 3 4))

(define (describe x)
  (when (> x 0)
    `(the number ,x doubled is ,(* x 2))))

; ( (greeting hello world)
;   (1 2 3 4 5)
;   (the number 7 doubled is 14) )
(list
  `(greeting hello ,name)
  `(1 ,@numbers 5)
  (describe 7))
