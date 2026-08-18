defmodule Combinators.Failure do
  @moduledoc """
  Tracks the *furthest* position a parse reached before failing, so that a
  failed `Parser.parse/2` can report where things went wrong and what was
  expected — instead of a bare `nil`.

  The tracker is process-local (stored in the process dictionary), so parses
  running in different processes never interfere. `Parser.parse/2` calls
  `reset/0` before a run and `deepest/0` afterwards; leaf combinators call
  `record/2` when they fail.

  Only the deepest failure is interesting: if two leaves fail, the one that
  consumed more input is almost always the more useful diagnostic. Failures at
  the same offset accumulate so the message can say "expected X, Y or Z".

  ## Turning tracking off

  Recording runs on *every* leaf failure, and a backtracking grammar fails
  constantly. When you only need to know *whether* the input parsed, pass
  `errors: false` to `Parser.parse/3`:

      Parser.parse(source, grammar, errors: false)

  Leaf combinators then skip recording, and a failed parse reports a generic
  message instead of a position and expectation set. The `{:ok, _}` result is
  unchanged.
  """

  @key :vortex_furthest_failure

  @doc """
  Clear any recorded failure for the current process, and choose whether this
  run records failures at all.

  With `track?` false a `:disabled` sentinel is stored under the same key that
  `record/2` already reads, so switching tracking off adds no extra lookup to
  the hot path.
  """
  @spec reset(boolean) :: :ok
  def reset(track? \\ true)

  def reset(true) do
    Process.delete(@key)
    :ok
  end

  def reset(false) do
    Process.put(@key, :disabled)
    :ok
  end

  @doc "Whether failure recording is enabled for the current process."
  @spec enabled?() :: boolean
  def enabled?, do: Process.get(@key) != :disabled

  @doc """
  Record that a parser expected `expected` at `state`, keeping only the
  furthest such failure. Always returns `nil` so leaf combinators can use it
  directly as their failure value.
  """
  @spec record(State.t(), binary) :: nil
  def record(%State{offset: offset, line: line, column: column}, expected) do
    case Process.get(@key) do
      {best, _line, _col, _expected} when offset < best ->
        # Shallower than the furthest failure so far — the hot path in a
        # backtracking grammar, and just one compare.
        :ok

      {best, best_line, best_col, expecteds} when offset == best ->
        Process.put(@key, {best, best_line, best_col, [expected | expecteds]})

      :disabled ->
        :ok

      _ ->
        Process.put(@key, {offset, line, column, [expected]})
    end

    nil
  end

  @doc """
  Replace the expectation at `state` with a single friendly `name`, unless a
  deeper failure has already been recorded. This is how `Combinators.label/2`
  turns a wall of low-level expectations into one readable message (like
  Parsec's `<?>`), while still deferring to any error found *after* input was
  consumed.
  """
  @spec relabel(State.t(), binary) :: nil
  def relabel(%State{offset: offset, line: line, column: column}, name) do
    case Process.get(@key) do
      {best, _line, _col, _expected} when offset < best -> :ok
      # Must not clobber the sentinel, or tracking would switch itself back on.
      :disabled -> :ok
      _ -> Process.put(@key, {offset, line, column, [name]})
    end

    nil
  end

  @doc """
  Return the deepest recorded failure as a map, or `nil` if none was recorded.
  The `:expected` list is de-duplicated and in the order the expectations were
  first seen.
  """
  @spec deepest() ::
          %{
            offset: non_neg_integer,
            line: pos_integer,
            column: non_neg_integer,
            expected: [binary]
          }
          | nil
  def deepest do
    case Process.get(@key) do
      {offset, line, column, expecteds} ->
        %{
          offset: offset,
          line: line,
          column: column,
          expected: expecteds |> Enum.reverse() |> Enum.uniq()
        }

      # `nil` (nothing recorded) or `:disabled` (tracking off).
      _ ->
        nil
    end
  end
end
