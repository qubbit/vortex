defmodule State do
  @moduledoc """
  Module to facilitate traversing and maintaining state of the input string
  """

  defstruct [:string, :offset]

  @doc """
  Create and return a new `State` with the input string and an offset of 0
  """
  def new(string) do
    %State{string: string, offset: 0}
  end

  @doc """
  Peek up to `offset + n` positions from the current offset and return that
  string slice
  """
  def peek(%State{offset: offset, string: string}, n) do
    String.slice(string, offset, n)
  end

  @doc """
  Advance the offset by `n` positions. This means we have consumed up to `n +
  offset` position of the input string
  """
  def read(%State{offset: offset} = state, n) do
    %{state | offset: offset + n}
  end

  @doc """
  Returns true if we have finished consuming the input string
  """
  def complete?(%State{offset: offset, string: string}) do
    offset == String.length(string)
  end
end
