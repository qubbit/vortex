defmodule Combinator do
  @moduledoc """
  This module provides fundamental combinators for matching and parsing
  strings. All public functions in this module return a function which takes a
  `State` struct with the original string and an offset from where the new
  matching should start. The return value of these inner functions is simply
  `nil` if no match was found. When a match has been found it will return a
  2-tuple `{nodes, new_state}`.

  `nodes` is a list where the head is the name of the combinator and the tail is
  a list of consumed substring by that combinator.

  `new_state` is the `State` struct with the original string and a new offset.
  """

  @type state :: %State{string: binary, offset: integer}

  @doc """
  Match a string and return a new `State` with the next offset
  """
  @spec str(string :: binary, visitor :: (any -> any) | nil) :: (state -> {[any], state} | nil)
  def str(string, visitor \\ nil) do
    fn state ->
      len = String.length(string)
      chunk = State.peek(state, len)

      if chunk == string do
        {[:str, hd(apply_visitor([chunk], visitor))], State.read(state, len)}
      end
    end
  end

  @doc """
  Attempt to match a single character against the given regex range or
  character class
  """
  @spec chr(pattern :: binary, visitor :: (any -> any) | nil) :: (state -> {[any], state} | nil)
  def chr(pattern, visitor \\ nil) do
    fn state ->
      chunk = State.peek(state, 1)

      if chunk =~ ~r{[#{pattern}]} do
        {[:chr, hd(apply_visitor([chunk], visitor))], State.read(state, 1)}
      end
    end
  end

  @doc """
  Match all the given combinators sequentially. If any of the combinators fails
  to parse, that is, it returns `nil`, this function will also return `nil`.
  One way to look at it as as a chain of logical conjunction:

  `parser_1 ∧ parser_2 ∧ ... ∧ parser_n`
  """
  @spec seq(parsers :: [function], visitor :: (any -> any) | nil) ::
          (state -> {[any], state} | nil)
  def seq(parsers, visitor \\ nil) do
    fn state ->
      {nodes, new_state} =
        Enum.reduce_while(parsers, {[], state}, fn parser, {acc_nodes, acc_state} ->
          case parser.(acc_state) do
            {node, new_state} -> {:cont, {acc_nodes ++ [node], new_state}}
            nil -> {:halt, {acc_nodes, nil}}
          end
        end)

      if new_state do
        {[:seq | apply_visitor(nodes, visitor)], new_state}
      end
    end
  end

  @doc """
  Return `nil` for negative numbers of repetitions
  """
  @spec rep(any(), n :: integer()) :: nil
  def rep(_, n) when n < 0 do
    nil
  end

  @doc """
  Repetition of minimum `n` occurences in the string that satisfies the given
  combinator. The function returned by this function will greedily match until
  no matches are found for the given combinator. If we have found at least `n`
  matches it's a success, else it's a failure and the inner function shall
  return `nil`.
  """
  @spec rep(parser :: function, visitor :: (any -> any) | nil) :: (state -> {[any], state} | nil)
  def rep(parser, n, visitor \\ nil) do
    fn state ->
      {_, new_state, nodes, count} = rep_recurse(parser, state, [], 0)

      if count >= n do
        {[:rep | apply_visitor(nodes, visitor)], new_state}
      end
    end
  end

  defp rep_recurse(parser, nil, nodes, count) do
    {parser, nil, nodes, count}
  end

  defp rep_recurse(parser, state, nodes, count) do
    result = parser.(state)

    case result do
      {node, new_state} -> rep_recurse(parser, new_state, nodes ++ [node], count + 1)
      nil -> {parser, state, nodes, count}
    end
  end

  @doc """
  Given a list of combinators returns success (2-tuple) if at least one of them
  satisfies the string starting at the given offset, else it's a failure
  (`nil`). All the combinators passed to this function start from the same
  offset in the string.

  One way to look at this combinator is as a chain of logical disjunction:

  `parser_1 ∨ parser_2 ∨ ... ∨  parser_n`
  """
  @spec alt(parsers :: [function], visitor :: (any -> any) | nil) ::
          (state -> {[any], state} | nil)
  def alt(parsers, visitor \\ nil) do
    fn state ->
      result =
        Enum.map(parsers, fn parser ->
          case parser.(state) do
            {nodes, new_state} -> {apply_visitor(nodes, visitor), new_state}
            _ -> nil
          end
        end)

      Enum.find(result, fn x -> !is_nil(x) end)
    end
  end

  def ref(name) do
    fn state ->
      apply(__MODULE__, name, [state])
    end
  end

  defp apply_visitor(nodes, visitor) when is_function(visitor) do
    Enum.map(nodes, visitor)
  end

  defp apply_visitor(nodes, _), do: nodes
end
