defmodule Calculator do
  @moduledoc """
  A small arithmetic expression evaluator built from the Vortex combinators.

  It parses and evaluates in one pass by having each combinator yield a *value*
  rather than a parse-tree node. Precedence and associativity are declared as an
  operator table and wired up by `Combinators.Expr.expression/2`; the atom is a
  number or a parenthesised expression.

  Supports `+ - * /`, parentheses, unary minus, integer and decimal literals,
  and arbitrary surrounding whitespace. Division yields an integer when it
  divides evenly, otherwise a float.

  ## Examples

      iex> Calculator.eval("1 + 2 * 3")
      {:ok, 7}

      iex> Calculator.eval("(1 + 2) * 3")
      {:ok, 9}

      iex> Calculator.eval("10 - 2 - 3")
      {:ok, 5}

      iex> match?({:error, _}, Calculator.eval("2 +"))
      true
  """

  import Combinators
  import Combinators.Builtin, only: [~>: 2, lexeme: 1, symbol: 1, whitespaced: 1]
  import Combinators.DSL
  import Combinators.Expr

  @doc """
  Parse and evaluate `source`, returning `{:ok, number}` or `{:error, reason}`.
  """
  @spec eval(binary) :: {:ok, number} | {:error, binary}
  def eval(source) when is_binary(source) do
    grammar = whitespaced(map(seq([expr(), eof()]), fn [_seq, value, _eof] -> value end))

    case Parser.parse(source, grammar) do
      {:ok, value} -> {:ok, value}
      {:error, _} = error -> error
    end
  rescue
    e in ArithmeticError -> {:error, Exception.message(e)}
  end

  @doc """
  Like `eval/1` but returns the number directly and raises on error.
  """
  @spec eval!(binary) :: number
  def eval!(source) when is_binary(source) do
    case eval(source) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # The whole precedence structure is declared as a table, tightest first.
  defp expr, do: expression(atom(), operator_table())

  defp operator_table do
    [
      [prefix("-", &(-&1))],
      [infixl("*", &*/2), infixl("/", &divide/2)],
      [infixl("+", &+/2), infixl("-", &-/2)]
    ]
  end

  # An atom is a number or a parenthesised expression, written with the
  # `choice`/`sequence` block macros.
  defp atom do
    choice do
      number()
      parenthesised()
    end
  end

  defp parenthesised do
    sequence do
      _ <- symbol("(")
      value <- lazy(&expr/0)
      _ <- symbol(")")
      return(value)
    end
  end

  # Written with the `~>` (map) operator and given a friendly label for errors.
  defp number do
    raw = seq([digits(), opt(seq([str("."), digits()]))])
    lexeme(label(text(raw) ~> (&to_number/1), "a number"))
  end

  defp digits, do: rep(char("0-9"), 1)

  defp to_number(text) do
    text = String.replace_prefix(text, "+", "")

    if String.contains?(text, ".") do
      String.to_float(text)
    else
      String.to_integer(text)
    end
  end

  defp divide(_a, 0), do: raise(ArithmeticError, message: "division by zero")

  defp divide(a, b) when is_integer(a) and is_integer(b) do
    if rem(a, b) == 0, do: div(a, b), else: a / b
  end

  defp divide(a, b), do: a / b
end
