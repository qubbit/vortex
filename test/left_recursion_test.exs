defmodule LeftRecursionTest do
  use ExUnit.Case
  import Combinators
  import Combinators.Builtin

  # A directly left-recursive, left-associative additive grammar that also
  # evaluates as it parses:  sum = sum "+" num | sum "-" num | num
  defp num, do: text(rep(char("0-9"), 1)) ~> (&String.to_integer/1)

  defp sum do
    rule(:sum, fn ->
      alt([
        seq([sum(), str("+"), num()]) ~> fn [_, a, _, b] -> a + b end,
        seq([sum(), str("-"), num()]) ~> fn [_, a, _, b] -> a - b end,
        num()
      ])
    end)
  end

  # Two cooperating left-recursive rules give precedence for free.
  defp expr do
    rule(:expr, fn ->
      alt([
        seq([expr(), str("+"), term()]) ~> fn [_, a, _, b] -> a + b end,
        seq([expr(), str("-"), term()]) ~> fn [_, a, _, b] -> a - b end,
        term()
      ])
    end)
  end

  defp term do
    rule(:term, fn ->
      alt([
        seq([term(), str("*"), factor()]) ~> fn [_, a, _, b] -> a * b end,
        seq([term(), str("/"), factor()]) ~> fn [_, a, _, b] -> div(a, b) end,
        factor()
      ])
    end)
  end

  defp factor do
    alt([
      num(),
      seq([str("("), lazy(&expr/0), str(")")]) ~> fn [_, _, v, _] -> v end
    ])
  end

  describe "direct left recursion" do
    test "a single base case still parses" do
      assert {:ok, 7} = Parser.parse("7", sum())
    end

    test "grows the seed across a chain" do
      assert {:ok, 6} = Parser.parse("1+2+3", sum())
    end

    test "is left-associative for subtraction" do
      # left:  ((10 - 2) - 3) = 5    right: (10 - (2 - 3)) = 11
      assert {:ok, 5} = Parser.parse("10-2-3", sum())
    end

    test "mixes operators left to right" do
      assert {:ok, 2} = Parser.parse("1-2+3", sum())
      assert {:ok, 20} = Parser.parse("100-50-25-5", sum())
    end
  end

  describe "precedence via two left-recursive rules" do
    test "multiplication binds tighter than addition" do
      assert {:ok, 14} = Parser.parse("2+3*4", expr())
      assert {:ok, 10} = Parser.parse("2*3+4", expr())
    end

    test "parentheses override precedence" do
      assert {:ok, 20} = Parser.parse("(2+3)*4", expr())
      assert {:ok, 21} = Parser.parse("((1+2)*(3+4))", expr())
    end

    test "division is left-associative" do
      assert {:ok, 10} = Parser.parse("100/5/2", expr())
    end
  end

  describe "failure and consumption" do
    test "fails cleanly on the empty input" do
      assert {:error, _} = Parser.parse("", sum())
    end

    test "a partial parse is reported, not silently accepted" do
      assert {:error, reason} = Parser.parse("1+", sum())
      assert reason =~ "line 1"
    end

    test "memo is reset between runs (offsets do not leak across parses)" do
      assert {:ok, 3} = Parser.parse("1+2", sum())
      assert {:ok, 12} = Parser.parse("5+7", sum())
      assert {:ok, 3} = Parser.parse("1+2", sum())
    end
  end

  describe "node-building (no value transform)" do
    # xs = xs "x" | "x"  — left-recursive, builds a left-nested tree of nodes.
    defp xs do
      rule(:xs, fn -> alt([seq([xs(), str("x")]), str("x")]) end)
    end

    test "consumes a whole run and nests to the left" do
      assert {:ok, tree} = Parser.parse("xxx", xs())
      # Outermost node is a seq whose left child is itself a seq (left nesting).
      assert [:seq, [:seq | _], [:lit_str, "x"]] = tree
    end
  end
end
