defmodule Combinators.Expr do
  @moduledoc """
  Build an expression parser from an operator-precedence table — the Vortex
  equivalent of Parsec's `buildExpressionParser` / Megaparsec's `makeExprParser`.

  `expression/2` takes a `term` parser (which yields a value) and a table of
  precedence levels, and wires up the layered parser so precedence and
  associativity come out right. The table is ordered **tightest-binding first**;
  operators on the same level share a precedence.

      import Combinators.Expr

      table = [
        [prefix("-", &(-&1))],
        [infixl("*", &*/2), infixl("/", &div/2)],
        [infixl("+", &+/2), infixl("-", &-/2)]
      ]

      expr = expression(number(), table)
      Parser.parse("2+3*4", expr)   #=> {:ok, 14}

  Each operator yields a function that is applied to the operands: infix
  operators a two-argument function, prefix/postfix a one-argument function.
  `infixl/2`, `infixr/2`, `infixn/2`, `prefix/2` and `postfix/2` build the
  descriptors; given a string token they match it (skipping surrounding
  whitespace); given a parser they use it as-is and take the supplied function.

  A single level should use one infix associativity (left, right, or none);
  prefix/postfix operators may be mixed in.
  """

  import Combinators
  import Combinators.Builtin, only: [one_of: 1, chainl1: 2, chainr1: 2]

  @type op :: {:infixl | :infixr | :infixn | :prefix | :postfix, function}

  @doc "Build an expression parser from a `term` and a precedence `table`."
  @spec expression(function, [[op]]) :: function
  def expression(term, table) do
    Enum.reduce(table, term, fn level, inner -> build_level(inner, level) end)
  end

  @doc "Left-associative infix operator."
  @spec infixl(binary | function, function) :: op
  def infixl(op, fun), do: {:infixl, op_parser(op, fun)}

  @doc "Right-associative infix operator."
  @spec infixr(binary | function, function) :: op
  def infixr(op, fun), do: {:infixr, op_parser(op, fun)}

  @doc "Non-associative infix operator (at most one at this level)."
  @spec infixn(binary | function, function) :: op
  def infixn(op, fun), do: {:infixn, op_parser(op, fun)}

  @doc "Prefix (unary) operator."
  @spec prefix(binary | function, function) :: op
  def prefix(op, fun), do: {:prefix, op_parser(op, fun)}

  @doc "Postfix (unary) operator."
  @spec postfix(binary | function, function) :: op
  def postfix(op, fun), do: {:postfix, op_parser(op, fun)}

  # --- internals -----------------------------------------------------------

  defp op_parser(token, fun) when is_binary(token) do
    map(seq([ws(), str(token), ws()]), fn _ -> fun end)
  end

  defp op_parser(parser, fun) when is_function(parser) do
    map(parser, fn _ -> fun end)
  end

  defp build_level(inner, level) do
    grouped = Enum.group_by(level, &elem(&1, 0), &elem(&1, 1))

    prefixes = Map.get(grouped, :prefix, [])
    postfixes = Map.get(grouped, :postfix, [])

    term = term_with_unary(inner, prefixes, postfixes)

    cond do
      infixls = grouped[:infixl] -> chainl1(term, alt(infixls))
      infixrs = grouped[:infixr] -> chainr1(term, alt(infixrs))
      infixns = grouped[:infixn] -> non_associative(term, alt(infixns))
      true -> term
    end
  end

  # term' = prefix* inner postfix*, applying the unary operators.
  defp term_with_unary(inner, [], []), do: inner

  defp term_with_unary(inner, prefixes, postfixes) do
    pre = collect(prefixes)
    post = collect(postfixes)

    bind(pre, fn pre_fns ->
      bind(inner, fn value ->
        bind(post, fn post_fns ->
          # Innermost prefix (nearest the term) applies first, then postfixes.
          value = Enum.reduce(Enum.reverse(pre_fns), value, fn f, acc -> f.(acc) end)
          return(Enum.reduce(post_fns, value, fn f, acc -> f.(acc) end))
        end)
      end)
    end)
  end

  # Zero or more unary operators, returned as a plain list of functions.
  defp collect([]), do: return([])

  defp collect(parsers) do
    map(rep(alt(parsers), 0), fn [:rep | fns] -> fns end)
  end

  defp non_associative(term, op) do
    bind(term, fn a ->
      alt([
        bind(op, fn fun -> bind(term, fn b -> return(fun.(a, b)) end) end),
        return(a)
      ])
    end)
  end

  defp ws, do: rep(one_of(" \t\n\r"), 0)
end
