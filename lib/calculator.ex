defmodule Calculator do
  @moduledoc """
  A small arithmetic expression evaluator built from the Vortex combinators.

  It parses and evaluates in one pass by having each combinator yield a *value*
  rather than a parse-tree node, wiring the operators together with
  `Combinators.Builtin.chainl1/2` so precedence and left-associativity come out
  right:

      expr   = term   (("+" | "-") term)*
      term   = factor (("*" | "/") factor)*
      factor = number | "(" expr ")" | "-" factor

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
  import Combinators.Builtin, only: [chainl1: 2, one_of: 1, "<|>": 2, "~>": 2]

  @doc """
  Parse and evaluate `source`, returning `{:ok, number}` or `{:error, reason}`.
  """
  @spec eval(binary) :: {:ok, number} | {:error, binary}
  def eval(source) when is_binary(source) do
    grammar = map(seq([ws(), expr(), ws(), eof()]), fn [_seq, _ws, value, _ws2, _eof] -> value end)

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

  defp expr, do: chainl1(lazy(&term/0), add_op())

  defp term, do: chainl1(lazy(&factor/0), mul_op())

  # Written with the `<|>` (choice) operator; the `map` callbacks take the whole
  # `[:seq | children]` node, so the value sits one position right of source order.
  defp factor do
    number()
    <|> map(seq([str("("), ws(), lazy(&expr/0), ws(), str(")")]), fn [_seq, _lp, _ws1, value, _ws2, _rp] -> value end)
    <|> map(seq([str("-"), ws(), lazy(&factor/0)]), fn [_seq, _minus, _ws, value] -> -value end)
  end

  defp add_op do
    alt([
      operator("+", &+/2),
      operator("-", &-/2)
    ])
  end

  defp mul_op do
    alt([
      operator("*", &*/2),
      operator("/", &divide/2)
    ])
  end

  # An operator parser yields the combining function, discarding surrounding
  # whitespace and the operator token itself.
  defp operator(token, fun) do
    map(seq([ws(), str(token), ws()]), fn _ -> fun end)
  end

  # Written with the `~>` (map) operator and given a friendly label for errors.
  defp number do
    raw = seq([opt(one_of("+-")), digits(), opt(seq([str("."), digits()]))])
    label(text(raw) ~> (&to_number/1), "a number")
  end

  defp digits, do: rep(char("0-9"), 1)

  defp ws, do: rep(one_of(" \t\n\r"), 0)

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
