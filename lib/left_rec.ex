defmodule Combinators.LeftRec do
  @moduledoc """
  Direct **left-recursion** support for the Vortex combinators, via packrat
  memoisation and seed growing (Warth, Douglass & Millstein, 2008 — simplified
  to the direct-recursion case).

  Ordinarily a rule that refers to itself at the same position — the classic
  `expr = expr "+" term | term` — loops forever. `rule/2` fixes that:

    * **Packrat memoisation.** A rule's result at a given offset is computed at
      most once per `Parser.parse/2` run and cached under `{name, offset}`.
    * **Seed growing.** When a rule re-enters itself at the same offset, the
      re-entry returns the current *seed* (initially failure, so the
      non-recursive branch is taken). The rule's body is then re-applied
      repeatedly, each pass letting the left-recursive branch extend the
      previous match, until it stops consuming more input.

  The result is a naturally left-associative parse:

      def add do
        rule(:add, fn ->
          alt([
            seq([add(), str("+"), num()]) ~> fn [_, a, _, b] -> a + b end,
            num()
          ])
        end)
      end

  Only *direct* left recursion is grown. Indirect cycles (`a -> b -> a`)
  terminate safely — the in-progress seed breaks the loop — and never return a
  wrong answer: an input that cannot be grown fully comes back as an error
  rather than a silently partial parse. They are not grown to completion,
  though. An alias cycle whose intermediate rule consumes nothing never gets
  past the base case, and a mutual cycle where both rules consume grows exactly
  one level. See `test/indirect_left_recursion_test.exs`, which pins this down.

  The per-run memo/seed tables live in the process dictionary and are cleared by
  `Parser.parse/2`; call `reset/0` yourself if you drive a `rule/2` parser
  without going through `Parser.parse/2`.
  """

  @memo :vortex_packrat
  @seeds :vortex_lr_seeds

  @doc "Clear the packrat memo and in-progress seed tables for this process."
  @spec reset() :: :ok
  def reset do
    Process.delete(@memo)
    Process.delete(@seeds)
    :ok
  end

  @doc """
  Wrap a named grammar rule so it can be left-recursive and is packrat-memoised.

  `builder` is a zero-arity function that returns the rule's parser; it is
  re-invoked as the seed grows. Reference the rule from inside `builder` by
  calling the same function again (which produces a `rule/2` with the same
  `name`), so the shared name is what ties the recursion together.
  """
  @spec rule(name :: term, builder :: (-> function)) :: (State.t() -> {[any], State.t()} | nil)
  def rule(name, builder) when is_function(builder, 0) do
    fn state -> apply_rule(name, builder, state) end
  end

  defp apply_rule(name, builder, state) do
    key = {name, state.offset}

    case seed_get(key) do
      {:seed, seed} ->
        # Left-recursive re-entry at the same position: return the current seed.
        seed

      nil ->
        case memo_get(key) do
          {:ok, result} -> result
          :error -> grow(name, builder, state, key)
        end
    end
  end

  defp grow(_name, builder, state, key) do
    seed_put(key, {:seed, nil})
    result = grow_loop(builder, state, key, nil)
    seed_delete(key)
    memo_put(key, result)
    result
  end

  defp grow_loop(builder, state, key, previous) do
    result = builder.().(state)

    if grew?(result, previous) do
      seed_put(key, {:seed, result})
      grow_loop(builder, state, key, result)
    else
      previous
    end
  end

  # A pass makes progress when it succeeds and consumes strictly more than the
  # previous seed did (a failure, or a shorter/equal match, means we're done).
  defp grew?(nil, _previous), do: false
  defp grew?({_node, %State{offset: _o}}, nil), do: true
  defp grew?({_node, %State{offset: o}}, {_pnode, %State{offset: po}}), do: o > po

  defp memo_get(key), do: Map.fetch(Process.get(@memo, %{}), key)
  defp memo_put(key, value), do: Process.put(@memo, Map.put(Process.get(@memo, %{}), key, value))

  defp seed_get(key), do: Map.get(Process.get(@seeds, %{}), key)
  defp seed_put(key, value), do: Process.put(@seeds, Map.put(Process.get(@seeds, %{}), key, value))
  defp seed_delete(key), do: Process.put(@seeds, Map.delete(Process.get(@seeds, %{}), key))
end
