defmodule Combinators.Grammar do
  @moduledoc """
  A tiny module DSL for defining a set of named grammar rules without the
  `rule(:name, fn -> … end)` ceremony or scattering `lazy/1` around recursive
  references.

  `use Combinators.Grammar`, then declare rules with `defrule/2`:

      defmodule Arith do
        use Combinators.Grammar
        import Combinators
        import Combinators.Builtin

        defrule :expr do
          alt([
            seq([expr(), str("+"), term()]) ~> fn [_, a, _, b] -> a + b end,
            term()
          ])
        end

        defrule :term do
          text(rep(char("0-9"), 1)) ~> &String.to_integer/1
        end
      end

      Parser.parse("1+2+3", Arith.expr())   #=> {:ok, 6}

  Each `defrule :name do … end` expands to a zero-arity function `name/0` that
  returns `Combinators.rule(:name, fn -> … end)`. Because it goes through
  `Combinators.LeftRec.rule/2`, rules are packrat-memoised and may be
  **left-recursive**, and you refer to other rules simply by calling them
  (`expr()`, `term()`) — no `lazy/1` needed, even for self-reference.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Combinators.Grammar, only: [defrule: 2]
    end
  end

  @doc """
  Define a named grammar rule. `name` must be an atom literal; the body is any
  parser expression and may reference other rules (including itself) by calling
  their generated `name/0` functions.
  """
  defmacro defrule(name, do: body) when is_atom(name) do
    quote do
      def unquote(name)() do
        Combinators.rule(unquote(name), fn -> unquote(body) end)
      end
    end
  end
end
