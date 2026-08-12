; Factorial
; ---------
; The classic recursive definition, plus an iterative version written with a
; tail-recursive helper and an accumulator.

(define (factorial n)
  (if (= n 0)
      1
      (* n (factorial (- n 1)))))

(define (factorial-iter n)
  (define (loop i acc)
    (if (> i n)
        acc
        (loop (+ i 1) (* acc i))))
  (loop 1 1))

; Both compute 10! => 3628800
(list (factorial 10) (factorial-iter 10))
