defmodule Combinators do
  @moduledoc """
  This module provides fundamental combinators for matching and parsing
  strings. All public functions in this module return a function which takes a
  `State`, and optionally, a `label` and a `visitor` function.

  `State`: struct with the original string and an offset from where the new
  matching should start.

  `label`: An identifier for this combinator. Defaults to the name of the
  combinator function

  `visitor`: A function that transforms the node created by this combinator.
  Defaults to `nil` (no transformation is done)

  Return value: An anonymous function. These anonymous functions simply return
  `nil` if no match was found. When a match has been found it will return a
  2-tuple `{nodes, new_state}`.

  `nodes` is a list where the head is the label of the combinator and the tail is
  a list of consumed substring by that combinator.

  `new_state` is the `State` struct with the original string and a new offset.
  """

  @type state :: %State{string: binary, offset: integer}

  @doc """
  Match a literal string and return a new `State` with the next offset
  """
  @spec str(string :: binary, visitor :: (any -> any) | nil) :: (state -> {[any], state} | nil)
  def str(string, label \\ :lit_str, visitor \\ nil) do
    fn state ->
      len = String.length(string)
      chunk = State.peek(state, len)

      if chunk == string do
        {[label, hd(apply_visitor([chunk], visitor))], State.read(state, len)}
      end
    end
  end

  @doc """
  Attempt to match a single character against the given regex range or
  character class
  """
  @spec char(pattern :: binary, visitor :: (any -> any) | nil) :: (state -> {[any], state} | nil)
  def char(pattern, label \\ :char, visitor \\ nil) do
    fn state ->
      chunk = State.peek(state, 1)

      if chunk =~ ~r{[#{pattern}]} do
        {[label, hd(apply_visitor([chunk], visitor))], State.read(state, 1)}
      end
    end
  end


  def opt(parser, label \\ :opt, visitor \\ nil) do
    fn state ->
      case parser.(state) do
        {node, new_state} -> {node, new_state}
        _ -> {[label, []], state}
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
  def seq(parsers, label \\ :seq, visitor \\ nil) do
    fn state ->
      {nodes, new_state} =
        Enum.reduce_while(parsers, {[], state}, fn parser, {acc_nodes, acc_state} ->
          case parser.(acc_state) do
            {node, new_state} -> {:cont, {acc_nodes ++ [node], new_state}}
            nil -> {:halt, {acc_nodes, nil}}
          end
        end)

      if new_state do
        {[label | apply_visitor(nodes, visitor)], new_state}
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
  def rep(parser, n, label \\ :rep, visitor \\ nil) do
    fn state ->
      {_, new_state, nodes, count} = rep_recurse(parser, state, [], 0)

      if count >= n do
        {[label | apply_visitor(nodes, visitor)], new_state}
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
  def alt(parsers, label \\ :alt, visitor \\ nil) do
    fn state ->
      Enum.find_value(parsers, fn parser ->
        parser.(state)
      end)
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

defmodule Combinators.Builtin do
  import Combinators

  # Some operators to alleviate verbosity
  def a <|> b when is_binary(a) and is_binary(b) do
    alt([str(a), str(b)])
  end

  def a <|> b when is_binary(a) and is_function(b) do
    alt([str(a), b])
  end

  def a <|> b when is_function(a) and is_binary(b) do
    alt([a, str(b)])
  end

  def a <|> b when is_function(a) and is_function(b) do
    alt([a, b])
  end

  def zero, do: str("0")
  def non_zero_digit, do: char("1-9")
  def digit, do: zero() <|> non_zero_digit()

  def positive_integer do
    seq([non_zero_digit(), digits()])
  end

  def negative_integer do
    seq([str("-"), non_zero_digit(), digits()])
  end

  def integer do
    alt([zero(), negative_integer(), positive_integer()])
  end

  def digits, do: rep(digit(), 1)

  def ws, do: rep(char("\R"), 1)

  def sep_by(separator), do: nil
  def many1, do: nil
  def choice, do: nil
  def between, do: nil
  def one_of, do: nil
end
