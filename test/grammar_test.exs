defmodule GrammarTest do
  use ExUnit.Case

  # A self-contained grammar defined entirely with `defrule`: left-recursive,
  # with precedence, and no `lazy/1` or explicit `rule/2` calls anywhere.
  defmodule Arith do
    use Combinators.Grammar
    import Combinators
    import Combinators.Builtin

    defrule :expr do
      alt([
        seq([expr(), str("+"), term()]) ~> fn [_, a, _, b] -> a + b end,
        seq([expr(), str("-"), term()]) ~> fn [_, a, _, b] -> a - b end,
        term()
      ])
    end

    defrule :term do
      alt([
        seq([term(), str("*"), factor()]) ~> fn [_, a, _, b] -> a * b end,
        seq([term(), str("/"), factor()]) ~> fn [_, a, _, b] -> div(a, b) end,
        factor()
      ])
    end

    defrule :factor do
      alt([
        text(rep(char("0-9"), 1)) ~> (&String.to_integer/1),
        seq([str("("), expr(), str(")")]) ~> fn [_, _, v, _] -> v end
      ])
    end
  end

  describe "defrule" do
    test "generates a zero-arity function per rule" do
      assert is_function(Arith.expr(), 1)
      assert is_function(Arith.term(), 1)
      assert is_function(Arith.factor(), 1)
    end

    test "a base rule parses" do
      assert {:ok, 7} = Parser.parse("7", Arith.expr())
    end

    test "rules refer to each other without lazy/1" do
      assert {:ok, 9} = Parser.parse("((1+2)*3)", Arith.expr())
    end
  end

  describe "left recursion through defrule" do
    test "is left-associative" do
      assert {:ok, 6} = Parser.parse("1+2+3", Arith.expr())
      assert {:ok, 5} = Parser.parse("10-2-3", Arith.expr())
    end

    test "respects precedence via cooperating rules" do
      assert {:ok, 14} = Parser.parse("2+3*4", Arith.expr())
      assert {:ok, 20} = Parser.parse("(2+3)*4", Arith.expr())
      assert {:ok, 10} = Parser.parse("100/5/2", Arith.expr())
    end
  end

  describe "errors" do
    test "a partial parse is reported" do
      assert {:error, reason} = Parser.parse("1+", Arith.expr())
      assert reason =~ "line 1"
    end
  end
end
