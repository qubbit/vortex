defmodule ExprTest do
  use ExUnit.Case
  import Combinators
  import Combinators.Builtin
  import Combinators.DSL
  import Combinators.Expr

  defp num, do: text(rep(char("0-9"), 1)) ~> (&String.to_integer/1)

  defp spaces, do: rep(one_of(" \t\n\r"), 0)

  defp atom do
    choice do
      num()

      sequence do
        _ <- str("(")
        _ <- spaces()
        v <- lazy(&full/0)
        _ <- spaces()
        _ <- str(")")
        return(v)
      end
    end
  end

  defp full do
    expression(atom(), [
      [prefix("-", &(-&1)), prefix("+", & &1)],
      [infixr("^", &Integer.pow/2)],
      [infixl("*", &*/2), infixl("/", &div/2)],
      [infixl("+", &+/2), infixl("-", &-/2)]
    ])
  end

  defp run(s), do: Parser.parse(s, full())

  describe "precedence" do
    test "multiplication binds tighter than addition" do
      assert {:ok, 14} = run("2+3*4")
      assert {:ok, 26} = run("2*3+4*5")
    end

    test "exponent binds tighter than multiplication" do
      assert {:ok, 18} = run("2*3^2")
    end

    test "parentheses override precedence" do
      assert {:ok, 20} = run("(2+3)*4")
    end
  end

  describe "associativity" do
    test "left-associative operators" do
      assert {:ok, 5} = run("10-2-3")
      assert {:ok, 10} = run("100/5/2")
    end

    test "right-associative exponent" do
      # 2 ^ (3 ^ 2) = 2 ^ 9 = 512, not (2 ^ 3) ^ 2 = 64
      assert {:ok, 512} = run("2^3^2")
    end
  end

  describe "unary operators" do
    test "prefix minus and plus" do
      assert {:ok, -5} = run("-5")
      assert {:ok, 5} = run("+5")
      assert {:ok, -6} = run("2*-3")
      assert {:ok, -7} = run("-(3+4)")
    end

    test "stacked prefixes" do
      assert {:ok, 5} = run("--5")
    end

    test "postfix operator" do
      fact = fn n -> Enum.reduce(1..max(n, 1), 1, &*/2) end

      bang =
        expression(num(), [
          [postfix("!", fact)]
        ])

      assert {:ok, 120} = Parser.parse("5!", bang)
    end
  end

  describe "non-associative" do
    test "allows a single application but not chaining" do
      eq =
        expression(num(), [
          [infixn("=", fn a, b -> if a == b, do: 1, else: 0 end)]
        ])

      assert {:ok, 1} = Parser.parse("2=2", eq)
      assert {:ok, 0} = Parser.parse("2=3", eq)
      assert {:error, _} = Parser.parse("2=2=2", eq)
    end
  end

  describe "whitespace" do
    test "operators tolerate surrounding whitespace" do
      assert {:ok, 7} = run("1 + 2 * 3")
      assert {:ok, 9} = run("( 1 + 2 ) * 3")
    end
  end
end
