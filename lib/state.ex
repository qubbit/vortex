defmodule State do
  @moduledoc """
  Module to facilitate traversing and maintaining state of the input string
  """

  defstruct [:string, :offset, :line, :column]

  @doc """
  Create and return a new `State` with the input string and an offset of 0
  """
  def new(string) do
    %State{string: string, offset: 0, line: 1, column: 0}
  end

  @doc """
  Peek up to `offset + n` positions from the current offset and return that
  string slice
  """
  def peek(%State{offset: o, string: s}, n) do
    String.slice(s, o, n)
  end

  @doc """
  Advance the offset by `n` positions. This means we have consumed up to `n +
  offset` position of the input string
  """
  def read(%State{offset: o, line: l, column: c} = state, n) do
    lines =
      state
      |> peek(n)
      |> String.split(~r/\R/)

    line_count = Enum.count(lines) - 1
    column_count = Enum.at(lines, -1) |> String.length()

    %{state | offset: o + n, line: l + line_count, column: c + column_count}
  end

  @doc """
  Returns true if we have finished consuming the input string
  """
  def complete?(%State{offset: o, string: s}) do
    o >= String.length(s)
  end
end
