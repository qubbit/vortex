defmodule Parser do
  @moduledoc """
  Entry point for running a grammar against an input string.

  A grammar is any parser built from `Combinators` — an anonymous function that
  takes a `State` and returns either `{nodes, new_state}` or `nil`.

  ## Examples

      iex> import Combinators
      iex> Parser.parse("hello", str("hello"))
      {:ok, [:lit_str, "hello"]}

      iex> import Combinators
      iex> Parser.parse("goodbye", str("hello"))
      {:error, ~s(line 1, column 1: expected "hello")}
  """

  @doc """
  Run `grammar` against `string`.

  Returns:

    * `{:ok, nodes}` when the grammar matches and consumes the whole input
    * `{:error, reason}` when the grammar fails to match, or matches only a
      prefix of the input (a partial parse). The reason points at the furthest
      position the parse reached and lists what was expected there.
  """
  @spec parse(binary, (State.t() -> {[any], State.t()} | nil)) ::
          {:ok, [any]} | {:error, binary}
  def parse(string, grammar) when is_binary(string) do
    Combinators.Failure.reset()
    Combinators.LeftRec.reset()
    state = State.new(string)

    case grammar.(state) do
      {nodes, new_state} ->
        if State.complete?(new_state) do
          {:ok, nodes}
        else
          {:error, error_message(new_state)}
        end

      nil ->
        {:error, error_message(state)}
    end
  end

  defp error_message(fallback_state) do
    case Combinators.Failure.deepest() do
      %{line: line, column: column, expected: expected} ->
        "line #{line}, column #{column + 1}: expected #{Enum.join(expected, ", ")}"

      nil ->
        "line #{fallback_state.line}, column #{fallback_state.column + 1}: unexpected input"
    end
  end
end
