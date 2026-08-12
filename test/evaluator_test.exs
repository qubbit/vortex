defmodule EvaluatorTest do
  use ExUnit.Case
  doctest Evaluator

  defp eval!(source), do: Evaluator.eval!(source)

  describe "self-evaluating literals" do
    test "numbers" do
      assert 42 = eval!("42")
      assert 3.14 = eval!("3.14")
      assert -7 = eval!("-7")
    end

    test "strings" do
      assert "hello" = eval!(~S["hello"])
    end

    test "booleans" do
      assert true == eval!("#t")
      assert false == eval!("#f")
    end

    test "quoted data" do
      assert [1, 2, 3] = eval!("'(1 2 3)")
      assert {:symbol, "foo"} = eval!("'foo")
      assert [] = eval!("'()")
    end
  end

  describe "arithmetic" do
    test "variadic sum and product" do
      assert 6 = eval!("(+ 1 2 3)")
      assert 24 = eval!("(* 2 3 4)")
      assert 0 = eval!("(+)")
      assert 1 = eval!("(*)")
    end

    test "subtraction negates a single argument and folds the rest" do
      assert -5 = eval!("(- 5)")
      assert 5 = eval!("(- 10 3 2)")
    end

    test "division stays integral when it divides evenly, else becomes a float" do
      assert 3 = eval!("(/ 12 4)")
      assert 3.5 = eval!("(/ 7 2)")
    end

    test "division by zero is a runtime error" do
      assert {:error, reason} = Evaluator.eval("(/ 1 0)")
      assert reason =~ "division by zero"
    end

    test "integer helpers" do
      assert 2 = eval!("(modulo 17 5)")
      assert 2 = eval!("(remainder 17 5)")
      assert 3 = eval!("(quotient 17 5)")
      assert 12 = eval!("(gcd 48 36)")
      assert 8 = eval!("(expt 2 3)")
      assert 5 = eval!("(abs -5)")
      assert 1 = eval!("(min 3 1 2)")
      assert 3 = eval!("(max 3 1 2)")
    end
  end

  describe "comparisons and predicates" do
    test "chained numeric comparison" do
      assert true == eval!("(< 1 2 3)")
      assert false == eval!("(< 1 3 2)")
      assert true == eval!("(= 2 2 2)")
      assert true == eval!("(>= 3 3 1)")
    end

    test "type predicates" do
      assert true == eval!("(null? '())")
      assert false == eval!("(null? '(1))")
      assert true == eval!("(pair? '(1))")
      assert true == eval!("(number? 3)")
      assert true == eval!("(string? \"x\")")
      assert true == eval!("(symbol? 'x)")
      assert true == eval!("(even? 4)")
      assert true == eval!("(odd? 3)")
      assert true == eval!("(zero? 0)")
    end

    test "not treats only #f as false" do
      assert false == eval!("(not 0)")
      assert false == eval!("(not '())")
      assert true == eval!("(not #f)")
    end
  end

  describe "list operations" do
    test "car, cdr and cons" do
      assert 1 = eval!("(car '(1 2 3))")
      assert [2, 3] = eval!("(cdr '(1 2 3))")
      assert [1, 2, 3] = eval!("(cons 1 '(2 3))")
    end

    test "list, append, length, reverse" do
      assert [1, 2, 3] = eval!("(list 1 2 3)")
      assert [1, 2, 3, 4] = eval!("(append '(1 2) '(3 4))")
      assert 3 = eval!("(length '(a b c))")
      assert [3, 2, 1] = eval!("(reverse '(1 2 3))")
    end

    test "list-ref and member" do
      assert 30 = eval!("(list-ref '(10 20 30 40) 2)")
      assert [2, 3] = eval!("(member 2 '(1 2 3))")
      assert false == eval!("(member 9 '(1 2 3))")
    end
  end

  describe "special forms" do
    test "if with and without an else branch" do
      assert {:symbol, "yes"} = eval!("(if #t 'yes 'no)")
      assert {:symbol, "no"} = eval!("(if #f 'yes 'no)")
      assert false == eval!("(if #f 'yes)")
    end

    test "cond with an else clause" do
      assert {:symbol, "big"} = eval!("(cond ((> 1 2) 'small) (else 'big))")
    end

    test "let binds in parallel" do
      assert 3 = eval!("(let ((a 1) (b 2)) (+ a b))")
    end

    test "let* binds sequentially" do
      assert 8 = eval!("(let* ((a 2) (b (* a 3))) (+ a b))")
    end

    test "and returns the last truthy value or #f" do
      assert 3 = eval!("(and 1 2 3)")
      assert false == eval!("(and 1 #f 3)")
    end

    test "or returns the first truthy value or #f" do
      assert 5 = eval!("(or #f 5 6)")
      assert false == eval!("(or #f #f)")
    end

    test "begin evaluates in order and yields the last value" do
      assert 3 = eval!("(begin 1 2 3)")
    end

    test "set! mutates a global binding" do
      assert 10 = eval!("(define x 1) (set! x 10) x")
    end
  end

  describe "functions and closures" do
    test "define and call a named function" do
      assert 81 = eval!("(define (square x) (* x x)) (square 9)")
    end

    test "anonymous lambda application" do
      assert 7 = eval!("((lambda (a b) (+ a b)) 3 4)")
    end

    test "closures capture their lexical environment" do
      assert 15 = eval!("(define (adder n) (lambda (x) (+ x n))) ((adder 10) 5)")
    end

    test "arity mismatch is reported" do
      assert {:error, reason} = Evaluator.eval("((lambda (x) x) 1 2)")
      assert reason =~ "arity"
    end

    test "higher-order builtins accept user functions" do
      assert [1, 4, 9] = eval!("(map (lambda (x) (* x x)) '(1 2 3))")
      assert [2, 4] = eval!("(filter even? '(1 2 3 4))")
      assert 10 = eval!("(foldl + 0 '(1 2 3 4))")
      assert 6 = eval!("(apply + '(1 2 3))")
    end
  end

  describe "recursion" do
    test "factorial" do
      assert 3628800 = eval!("(define (f n) (if (= n 0) 1 (* n (f (- n 1))))) (f 10)")
    end

    test "tree-recursive fibonacci" do
      src = "(define (fib n) (cond ((< n 2) n) (else (+ (fib (- n 1)) (fib (- n 2)))))) (fib 15)"
      assert 610 = eval!(src)
    end

    test "mutual recursion" do
      src = """
      (define (ev? n) (if (= n 0) #t (od? (- n 1))))
      (define (od? n) (if (= n 0) #f (ev? (- n 1))))
      (list (ev? 10) (od? 10))
      """

      assert [true, false] = eval!(src)
    end
  end

  describe "errors" do
    test "unbound symbols are reported" do
      assert {:error, reason} = Evaluator.eval("nope")
      assert reason =~ "unbound"
    end

    test "calling a non-procedure is reported" do
      assert {:error, reason} = Evaluator.eval("(1 2 3)")
      assert reason =~ "not a procedure"
    end

    test "parse errors propagate" do
      assert {:error, _} = Evaluator.eval("(+ 1")
    end
  end

  describe "render/1" do
    test "renders values in Scheme surface syntax" do
      assert "()" = Evaluator.render([])
      assert "(1 2 3)" = Evaluator.render([1, 2, 3])
      assert "#t" = Evaluator.render(true)
      assert "foo" = Evaluator.render({:symbol, "foo"})
      assert "hi" = Evaluator.render("hi")
    end
  end

  describe "example programs" do
    test "quicksort sorts a list" do
      assert {:ok, [1, 1, 2, 3, 3, 4, 5, 5, 5, 6, 9]} =
               Evaluator.eval_file("examples/quicksort.lisp")
    end

    test "factorial computes 10!" do
      assert {:ok, [3_628_800, 3_628_800]} = Evaluator.eval_file("examples/factorial.lisp")
    end

    test "fibonacci produces the sequence" do
      assert {:ok, [55, [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]]} =
               Evaluator.eval_file("examples/fibonacci.lisp")
    end

    test "higher-order example" do
      assert {:ok, [[1, 4, 9, 16, 25, 36, 49, 64, 81, 100], [2, 4, 6, 8, 10], 55, 5.5]} =
               Evaluator.eval_file("examples/higher_order.lisp")
    end

    test "classic algorithms" do
      assert {:ok, [12, 9, 45, 30, true]} = Evaluator.eval_file("examples/classics.lisp")
    end
  end
end
