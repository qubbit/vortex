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
      else
        Combinators.Failure.record(state, ~s("#{string}"))
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
      else
        Combinators.Failure.record(state, "a character in [#{pattern}]")
      end
    end
  end

  @doc """
  Match any single character. Fails (returns `nil`) only at the end of the
  input where there is nothing left to consume.
  """
  @spec any(label :: atom) :: (state -> {[any], state} | nil)
  def any(label \\ :any) do
    fn state ->
      chunk = State.peek(state, 1)

      if chunk != "" do
        {[label, chunk], State.read(state, 1)}
      else
        Combinators.Failure.record(state, "any character")
      end
    end
  end

  @doc """
  Succeed (consuming nothing) only at the end of the input. Combine it with a
  grammar to require that the whole string is consumed.
  """
  @spec eof(label :: atom) :: (state -> {[any], state} | nil)
  def eof(label \\ :eof) do
    fn state ->
      if State.complete?(state) do
        {[label, []], state}
      else
        Combinators.Failure.record(state, "end of input")
      end
    end
  end

  @doc """
  Positive lookahead: succeed, consuming no input, when `parser` would match at
  the current position. Fails otherwise.
  """
  @spec followed_by(parser :: function) :: (state -> {[any], state} | nil)
  def followed_by(parser) do
    fn state ->
      case parser.(state) do
        {_nodes, _new_state} -> {[:followed_by, []], state}
        nil -> nil
      end
    end
  end

  @doc """
  Negative lookahead: succeed, consuming no input, when `parser` would **not**
  match at the current position. Fails otherwise.
  """
  @spec not_followed_by(parser :: function) :: (state -> {[any], state} | nil)
  def not_followed_by(parser) do
    fn state ->
      case parser.(state) do
        nil -> {[:not_followed_by, []], state}
        {_nodes, _new_state} -> Combinators.Failure.record(state, "a negative lookahead to fail")
      end
    end
  end

  @doc """
  Make `parser` optional. On a match the inner node is returned untouched; when
  it fails an empty node `[label, []]` is returned and no input is consumed, so
  an `opt` combinator never fails.
  """
  @spec opt(parser :: function, label :: atom) :: (state -> {[any], state})
  def opt(parser, label \\ :opt) do
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
  @spec alt(parsers :: [function]) :: (state -> {[any], state} | nil)
  def alt(parsers) do
    fn state ->
      Enum.find_value(parsers, fn parser ->
        parser.(state)
      end)
    end
  end

  @doc """
  Reference a parser by the name of a zero-arity function on this module. The
  parser is looked up and built lazily, which lets grammars refer to rules that
  are defined later or that refer back to themselves.
  """
  def ref(name) do
    fn state ->
      apply(__MODULE__, name, [state])
    end
  end

  @doc """
  Defer building a parser until it is applied to a `State`. Wrap self- or
  mutually-recursive rules in `lazy/1` so the parser tree is only expanded on
  demand instead of looping forever while it is being constructed.

      lazy(fn -> expression() end)
  """
  @spec lazy((-> function)) :: (state -> {[any], state} | nil)
  def lazy(fun) do
    fn state -> fun.().(state) end
  end

  @doc """
  Transform the node produced by `parser` with `fun`. When `parser` fails the
  failure is propagated unchanged, otherwise `fun` is applied to the node and
  the same `new_state` is returned.
  """
  @spec map(parser :: function, fun :: (any -> any)) :: (state -> {[any], state} | nil)
  def map(parser, fun) do
    fn state ->
      case parser.(state) do
        {node, new_state} -> {fun.(node), new_state}
        _ -> nil
      end
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
    seq([non_zero_digit(), rep(digit(), 0)])
  end

  def negative_integer do
    seq([str("-"), non_zero_digit(), rep(digit(), 0)])
  end

  def integer do
    alt([zero(), negative_integer(), positive_integer()])
  end

  def digits, do: rep(digit(), 1)

  def ws, do: rep(char("\R"), 1)

  @doc """
  Match `parser` zero or more times, greedily. Always succeeds.
  """
  def many(parser), do: rep(parser, 0)

  @doc """
  Match `parser` one or more times, greedily. Fails if there is not at least
  one match.
  """
  def many1(parser), do: rep(parser, 1)

  @doc """
  Alias for `Combinators.alt/1`: succeed with the first parser in `parsers`
  that matches.
  """
  def choice(parsers), do: alt(parsers)

  @doc """
  Match `parser` wrapped between `open` and `close`. All three must match for
  the sequence to succeed.
  """
  def between(open, close, parser), do: seq([open, parser, close])

  @doc """
  Match one or more occurrences of `parser` separated by `separator`, e.g. the
  comma-separated arguments of a call. The separators are kept in the resulting
  node list.
  """
  def sep_by1(parser, separator) do
    seq([parser, rep(seq([separator, parser]), 0)])
  end

  @doc """
  Like `sep_by1/2`, but also succeeds (consuming nothing) when there are zero
  occurrences of `parser`.
  """
  def sep_by(parser, separator) do
    opt(sep_by1(parser, separator))
  end

  @doc """
  Match a single character that appears anywhere in `chars`. Fails at the end of
  the input or when the next character is not in the set.
  """
  def one_of(chars) when is_binary(chars) do
    fn state ->
      c = State.peek(state, 1)

      if c != "" and String.contains?(chars, c) do
        {[:one_of, c], State.read(state, 1)}
      else
        Combinators.Failure.record(state, ~s(one of "#{chars}"))
      end
    end
  end

  @doc """
  Match a single character that does **not** appear in `chars`. Fails at the end
  of the input or when the next character is in the set.
  """
  def none_of(chars) when is_binary(chars) do
    fn state ->
      c = State.peek(state, 1)

      if c != "" and not String.contains?(chars, c) do
        {[:none_of, c], State.read(state, 1)}
      else
        Combinators.Failure.record(state, ~s(a character other than "#{chars}"))
      end
    end
  end

  @doc """
  Match `parser` exactly `n` times. Fails if fewer than `n` matches are found.
  """
  def count(n, parser) when is_integer(n) and n >= 0 do
    fn state ->
      result =
        Enum.reduce_while(1..n//1, {[], state}, fn _i, {nodes, st} ->
          case parser.(st) do
            {node, st2} -> {:cont, {nodes ++ [node], st2}}
            nil -> {:halt, :fail}
          end
        end)

      case result do
        :fail -> nil
        {nodes, st} -> {[:count | nodes], st}
      end
    end
  end

  @doc """
  Match `parser` greedily between `min` and `max` times (inclusive). Fails if
  fewer than `min` matches are found; stops after `max`.
  """
  def rep_range(parser, min, max)
      when is_integer(min) and is_integer(max) and min >= 0 and max >= min do
    fn state ->
      {nodes, st, matched} = rep_range_collect(parser, state, [], 0, max)

      if matched >= min do
        {[:rep_range | nodes], st}
      else
        Combinators.Failure.record(state, "at least #{min} repetition(s)")
      end
    end
  end

  defp rep_range_collect(_parser, state, nodes, count, max) when count >= max do
    {nodes, state, count}
  end

  defp rep_range_collect(parser, state, nodes, count, max) do
    case parser.(state) do
      {node, st2} -> rep_range_collect(parser, st2, nodes ++ [node], count + 1, max)
      nil -> {nodes, state, count}
    end
  end
end
