; Classic algorithms
; ------------------
; A grab-bag of textbook recursive definitions exercising integer math,
; list building and mutual/self recursion.

; Greatest common divisor (Euclid's algorithm).
(define (my-gcd a b)
  (if (= b 0) a (my-gcd b (modulo a b))))

; Ackermann's function - small arguments only, it grows explosively.
(define (ackermann m n)
  (cond ((= m 0) (+ n 1))
        ((= n 0) (ackermann (- m 1) 1))
        (else (ackermann (- m 1) (ackermann m (- n 1))))))

; Build the list (a a+1 ... b-1).
(define (range a b)
  (if (>= a b) '() (cons a (range (+ a 1) b))))

; Sum a list with an explicit fold.
(define (sum lst) (foldl + 0 lst))

; Mutual recursion.
(define (my-even? n) (if (= n 0) #t (my-odd?  (- n 1))))
(define (my-odd?  n) (if (= n 0) #f (my-even? (- n 1))))

; (12 9 45 30 #t)
(list (my-gcd 48 36)
      (ackermann 2 3)
      (sum (range 1 10))
      (foldl + 0 (map (lambda (x) (* x x)) (range 1 5)))
      (my-even? 10))
