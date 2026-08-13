defmodule Combinators.DSL do
  @moduledoc """
  Block macros that make grammars read top-to-bottom.

  `import Combinators.DSL` to use them.

  ## `sequence do … end`

  Do-notation for `seq`: run parsers in order, bind the results you care about
  with `<-`, and produce a value with `return`. It desugars to
  `Combinators.bind/2` and `Combinators.return/1`.

      sequence do
        _     <- str("(")
        value <- expr()
        _     <- str(")")
        return value
      end

  A line without `<-` still runs its parser and discards the result. The bound
  pattern is an ordinary Elixir pattern, so you can destructure a node inline.

  ## `choice do … end`

  One alternative per line — sugar for `Combinators.alt/1`:

      choice do
        number()
        string_lit()
        symbol()
      end
  """

  @doc "Do-notation for sequencing parsers; see the module doc."
  defmacro sequence(do: block) do
    block
    |> statements()
    |> build_sequence()
  end

  @doc "First-match choice over one alternative per line; see the module doc."
  defmacro choice(do: block) do
    alternatives = statements(block)

    quote do
      Combinators.alt([unquote_splicing(alternatives)])
    end
  end

  defp statements({:__block__, _meta, stmts}), do: stmts
  defp statements(single), do: [single]

  defp build_sequence([last]), do: finalize(last)

  defp build_sequence([{:<-, _meta, [pattern, parser]} | rest]) do
    quote do
      Combinators.bind(unquote(parser), fn unquote(pattern) -> unquote(build_sequence(rest)) end)
    end
  end

  defp build_sequence([statement | rest]) do
    quote do
      Combinators.bind(unquote(statement), fn _ -> unquote(build_sequence(rest)) end)
    end
  end

  # The final line is the result. `return expr` becomes a pure parser; anything
  # else is taken to be a parser already.
  defp finalize({:return, _meta, [expr]}), do: quote(do: Combinators.return(unquote(expr)))
  defp finalize(other), do: other
end
