; Higher-order functions
; ----------------------
; map / filter / foldl over a list, plus a couple of small definitions built
; on top of them.

(define (square x) (* x x))

(define (sum lst) (foldl + 0 lst))

(define (average lst)
  (/ (sum lst) (length lst)))

(define nums (list 1 2 3 4 5 6 7 8 9 10))

; ((1 4 9 16 25 36 49 64 81 100)   ; squares
;  (2 4 6 8 10)                     ; evens
;  55                              ; sum
;  11/2 -> 5.5)                     ; average
(list (map square nums)
      (filter even? nums)
      (sum nums)
      (average nums))
