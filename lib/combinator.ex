defmodule Combinator do
  @moduledoc """
  This module provides fundamental combinators for matching and parsing
  strings. All functions in this module return a function which takes a `State`
  struct with the original string and an offset from where the new matching
  should start. The return value of these inner functions is simply `nil` if no
  match was found. When a match has been found it will return a 2-tuple `{node,
  new_state}`.

  `node` is a list where the head is the name of the combinator and the tail is
  a list of consumed substring by that combinator.

  `new_state` is the `State` struct with the original string and a new offset.
  """

  @doc """
  Match a string and return a new `State` with the next offset
  """
  def str(string) do
    fn state ->
      len = String.length(string)
      chunk = State.peek(state, len)

      if chunk == string do
        [[:str, chunk], State.read(state, len)]
      end
    end
  end

  @doc """
  Match a single character given a regex pattern
  """
  def chr(pattern) do
    fn state ->
      chunk = State.peek(state, 1)

      if chunk =~ ~r{[#{pattern}]} do
        [[:chr, chunk], State.read(state, 1)]
      end
    end
  end

  @doc """
  Match all the given combinators sequentially. If any of the combinators fails
  to parse, that is, it returns `nil`, this function will also return `nil`.
  One way to look at it as as a chain of logical conjunction:

  `parser_1 ∧ parser_2 ∧ ... ∧ parser_n`
  """
  def seq(parsers) do
    fn state ->
      result =
        Enum.reduce(parsers, {[], state}, fn parser, {acc_nodes, acc_state} ->
          [node, new_state] = parser.(acc_state)
          {acc_nodes ++ [node], new_state}
        end)

      {nodes, new_state} = result

      if new_state do
        [[:seq | nodes], new_state]
      end
    end
  end

  @doc """
  Return `nil` for negative numbers of repetitions
  """
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
  def rep(parser, n) do
    fn state ->
      {_, new_state, nodes, count} = rep_recurse(parser, state, [], 0)

      if count >= n do
        [[:rep | nodes], new_state]
      end
    end
  end

  defp rep_recurse(parser, nil, nodes, count) do
    {parser, nil, nodes, count}
  end

  defp rep_recurse(parser, state, nodes, count) do
    result = parser.(state)

    case result do
      [node, new_state] -> rep_recurse(parser, new_state, nodes ++ [node], count + 1)
      nil -> {parser, state, nodes, count}
    end
  end

  @doc """
  Given a list of combinators if at least of them satisfies the string starting
  at that offset it's a success, else it's a failure.
  """
  def alt(parsers) do
    fn state ->
      result =
        Enum.map(parsers, fn parser ->
          parser.(state)
        end)

      Enum.find(result, fn x -> !is_nil(x) end)
    end
  end
end
