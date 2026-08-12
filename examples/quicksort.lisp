; Quicksort
; ---------
; Sort a list of numbers by partitioning around a pivot and recursively
; sorting the smaller and larger halves. Demonstrates recursion, `let`,
; closures (the lambdas capture `pivot`), and the `filter`/`append` builtins.

(define (quicksort lst)
  (if (null? lst)
      '()
      (let ((pivot (car lst))
            (rest  (cdr lst)))
        (append
         (quicksort (filter (lambda (x) (<  x pivot)) rest))
         (list pivot)
         (quicksort (filter (lambda (x) (>= x pivot)) rest))))))

; => (1 1 2 3 3 4 5 5 5 6 9)
(quicksort '(3 1 4 1 5 9 2 6 5 3 5))
