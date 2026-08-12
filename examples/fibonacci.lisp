; Fibonacci
; ---------
; A naive tree-recursive Fibonacci defined with `cond`, and a fast linear
; version that accumulates the running pair. `fib-list` maps the linear
; version over a range to show the sequence.

(define (fib n)
  (cond ((= n 0) 0)
        ((= n 1) 1)
        (else (+ (fib (- n 1)) (fib (- n 2))))))

(define (fib-fast n)
  (define (loop a b count)
    (if (= count 0)
        a
        (loop b (+ a b) (- count 1))))
  (loop 0 1 n))

(define (range a b)
  (if (>= a b)
      '()
      (cons a (range (+ a 1) b))))

; fib 10 => 55, and the first ten Fibonacci numbers via the fast version.
(list (fib 10)
      (map fib-fast (range 0 10)))
