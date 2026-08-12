defmodule EvaluatorExtrasTest do
  @moduledoc "Covers the quasiquote, when/unless, tail-call and REPL additions."
  use ExUnit.Case

  defp eval!(source), do: Evaluator.eval!(source)

  describe "when / unless" do
    test "when evaluates its body only if the test is truthy" do
      assert {:symbol, "yes"} = eval!("(when (> 3 2) 'yes)")
      assert false == eval!("(when (< 3 2) 'yes)")
    end

    test "unless evaluates its body only if the test is falsy" do
      assert {:symbol, "ok"} = eval!("(unless (< 3 2) 'ok)")
      assert false == eval!("(unless (> 3 2) 'ok)")
    end

    test "the body is an implicit sequence returning its last value" do
      assert 3 = eval!("(when #t 1 2 3)")
    end
  end

  describe "quasiquote" do
    test "behaves like quote with no unquotes" do
      assert [{:symbol, "a"}, {:symbol, "b"}] = eval!("`(a b)")
    end

    test "unquote splices in an evaluated value" do
      assert [1, 10, 3] = eval!("(define x 10) `(1 ,x 3)")
    end

    test "unquote can hold an arbitrary expression" do
      assert [{:symbol, "sum"}, 7] = eval!("`(sum ,(+ 3 4))")
    end

    test "unquote-splicing expands a list in place" do
      assert [1, 2, 3, 4] = eval!("(define ys '(2 3)) `(1 ,@ys 4)")
    end

    test "combines unquote and unquote-splicing" do
      assert [0, 1, 2, 3, 99] = eval!("(define mid '(1 2 3)) `(0 ,@mid ,(* 33 3))")
    end

    test "unquote outside quasiquote is an error" do
      assert {:error, reason} = Evaluator.eval(",x")
      assert reason =~ "unquote"
    end
  end

  describe "tail-call optimization" do
    test "a deep tail-recursive loop does not overflow the stack" do
      program = """
      (define (loop i acc)
        (if (= i 0) acc (loop (- i 1) (+ acc 1))))
      (loop 1000000 0)
      """

      assert 1_000_000 = eval!(program)
    end

    test "tail calls through cond also loop" do
      program = """
      (define (count-down n)
        (cond ((= n 0) 'done)
              (else (count-down (- n 1)))))
      (count-down 500000)
      """

      assert {:symbol, "done"} = eval!(program)
    end
  end

  describe "persistent environment" do
    test "state carries across eval_string/2 calls" do
      env = Evaluator.start_env()

      try do
        assert {:ok, {:symbol, "counter"}} = Evaluator.eval_string(env, "(define counter 0)")
        assert {:ok, 5} = Evaluator.eval_string(env, "(set! counter (+ counter 5))")
        assert {:ok, 8} = Evaluator.eval_string(env, "(+ counter 3)")
      after
        Evaluator.stop_env(env)
      end
    end

    test "eval_string reports errors without tearing down the environment" do
      env = Evaluator.start_env()

      try do
        assert {:error, _} = Evaluator.eval_string(env, "(bogus)")
        assert {:ok, 3} = Evaluator.eval_string(env, "(+ 1 2)")
      after
        Evaluator.stop_env(env)
      end
    end
  end

  describe "example program" do
    test "quasiquote.lisp" do
      assert {:ok,
              [
                [{:symbol, "greeting"}, {:symbol, "hello"}, {:symbol, "world"}],
                [1, 2, 3, 4, 5],
                [
                  {:symbol, "the"},
                  {:symbol, "number"},
                  7,
                  {:symbol, "doubled"},
                  {:symbol, "is"},
                  14
                ]
              ]} = Evaluator.eval_file("examples/quasiquote.lisp")
    end
  end
end
