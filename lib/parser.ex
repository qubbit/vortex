defmodule Parser do
  @moduledoc """
  Entry point for running a grammar against an input string.

  A grammar is any parser built from `Combinators` — an anonymous function that
  takes a `State` and returns either `{nodes, new_state}` or `nil`.
  """

  @doc """
  Run `grammar` against `string`.

  Returns:

    * `{:ok, nodes}` when the grammar matches and consumes the whole input
    * `{:error, reason}` when the grammar fails to match, or matches only a
      prefix of the input (a partial parse)
  """
  @spec parse(binary, (State.t() -> {[any], State.t()} | nil)) ::
          {:ok, [any]} | {:error, binary}
  def parse(string, grammar) when is_binary(string) do
    state = State.new(string)

    case grammar.(state) do
      {nodes, new_state} ->
        if State.complete?(new_state) do
          {:ok, nodes}
        else
          {:error, "unexpected input at offset #{new_state.offset}"}
        end

      nil ->
        {:error, "no match at offset 0"}
    end
  end
end
