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
    # Compile the character-class regex once, when the combinator is built,
    # rather than on every character it is asked to match.
    regex = Regex.compile!("[#{pattern}]")
    expected = "a character in [#{pattern}]"

    fn state ->
      chunk = State.peek(state, 1)

      if chunk =~ regex do
        {[label, hd(apply_visitor([chunk], visitor))], State.read(state, 1)}
      else
        Combinators.Failure.record(state, expected)
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
      # Accumulate nodes by prepending (O(1)) and reverse once at the end,
      # instead of appending to the tail (O(n) per step, O(n^2) overall).
      {nodes, new_state} =
        Enum.reduce_while(parsers, {[], state}, fn parser, {acc_nodes, acc_state} ->
          case parser.(acc_state) do
            {node, new_state} -> {:cont, {[node | acc_nodes], new_state}}
            nil -> {:halt, {acc_nodes, nil}}
          end
        end)

      if new_state do
        {[label | apply_visitor(Enum.reverse(nodes), visitor)], new_state}
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
      # `rep_recurse` collects nodes in reverse (prepending is O(1)); reverse
      # once here so the overall cost is linear rather than quadratic.
      {_, new_state, nodes, count} = rep_recurse(parser, state, [], 0)

      if count >= n do
        {[label | apply_visitor(Enum.reverse(nodes), visitor)], new_state}
      end
    end
  end

  defp rep_recurse(parser, nil, nodes, count) do
    {parser, nil, nodes, count}
  end

  defp rep_recurse(parser, state, nodes, count) do
    result = parser.(state)

    case result do
      {node, new_state} -> rep_recurse(parser, new_state, [node | nodes], count + 1)
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
  Define a named, packrat-memoised grammar rule that may be **left-recursive**.
  See `Combinators.LeftRec` for the full story. Delegates to
  `Combinators.LeftRec.rule/2` so it is available wherever `Combinators` is
  imported.

      def add do
        rule(:add, fn -> alt([seq([add(), str("+"), num()]), num()]) end)
      end
  """
  defdelegate rule(name, builder), to: Combinators.LeftRec

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

  @doc """
  Monadic bind: run `parser`, then feed its result node to `fun`, which returns
  the next parser to run from the new position. Fails if `parser` fails. This is
  the primitive the `Combinators.DSL.sequence/1` macro desugars to.
  """
  @spec bind(parser :: function, fun :: (any -> function)) :: (state -> {any, state} | nil)
  def bind(parser, fun) do
    fn state ->
      case parser.(state) do
        {node, new_state} -> fun.(node).(new_state)
        nil -> nil
      end
    end
  end

  @doc """
  A parser that always succeeds with `value`, consuming no input (`return`/`pure`
  in the applicative sense). Pairs with `bind/2` and `sequence`.
  """
  @spec return(any) :: (state -> {any, state})
  def return(value), do: fn state -> {value, state} end

  @doc "Alias for `return/1`."
  @spec pure(any) :: (state -> {any, state})
  def pure(value), do: return(value)

  @doc """
  Replace `parser`'s node with the exact substring it consumed. Handy for
  turning a structured match (a number, an identifier) back into raw text
  before converting it to a value.
  """
  @spec text(parser :: function) :: (state -> {binary, state} | nil)
  def text(parser) do
    fn state ->
      case parser.(state) do
        {node, new_state} -> {collect_text(node), new_state}
        _ -> nil
      end
    end
  end

  @doc false
  def collect_text(binary) when is_binary(binary), do: binary
  def collect_text(list) when is_list(list), do: list |> Enum.map(&collect_text/1) |> Enum.join()
  def collect_text(_other), do: ""

  @doc """
  Give `parser` a human-readable `name` for error messages. If it fails without
  consuming input, the reported expectation becomes just `name` instead of the
  underlying low-level tokens — the equivalent of Parsec's `<?>`.

      Parser.parse("!", label(digits(), "a number"))
      #=> {:error, "line 1, column 1: expected a number"}
  """
  @spec label(parser :: function, name :: binary) :: (state -> {[any], state} | nil)
  def label(parser, name) do
    fn state ->
      case parser.(state) do
        {_node, _new_state} = ok -> ok
        nil -> Combinators.Failure.relabel(state, name)
      end
    end
  end

  @doc """
  Run `left` then `right`, keeping only `left`'s node (Parsec's `<*`). Both must
  match.
  """
  @spec keep_left(function, function) :: (state -> {[any], state} | nil)
  def keep_left(left, right) do
    map(seq([left, right]), fn [_seq, kept, _dropped] -> kept end)
  end

  @doc """
  Run `left` then `right`, keeping only `right`'s node (Parsec's `*>`). Both
  must match.
  """
  @spec keep_right(function, function) :: (state -> {[any], state} | nil)
  def keep_right(left, right) do
    map(seq([left, right]), fn [_seq, _dropped, kept] -> kept end)
  end

  defp apply_visitor(nodes, visitor) when is_function(visitor) do
    Enum.map(nodes, visitor)
  end

  defp apply_visitor(nodes, _), do: nodes
end

defmodule Combinators.Builtin do
  @moduledoc """
  Derived combinators, lexical helpers, and infix operators layered on top of
  `Combinators`.

  ## Operators

  Each operator is only sugar for a named function, so both spellings work and
  you can mix them freely:

  | Operator | Function | Meaning (Parsec analogue) |
  | --- | --- | --- |
  | `a <\|> b` | `Combinators.alt/1` | ordered choice (`<\|>`) |
  | `p ~> f` | `Combinators.map/2` | transform the result (`<$>`) |
  | `a ~>> b` | `Combinators.keep_right/2` | sequence, keep the right (`*>`) |
  | `a <<~ b` | `Combinators.keep_left/2` | sequence, keep the left (`<*`) |

  Parsec's `<?>` (label) and `<$>`/`<*>` are not valid Elixir operators, so use
  the `Combinators.label/2`, `map/2`, `keep_left/2` and `keep_right/2`
  functions for those.

  Note: all four operators share **one** precedence level and are
  left-associative in Elixir (unlike Haskell, where `<$>` binds tighter than
  `<|>`). So `a <|> b ~> f` parses as `(a <|> b) ~> f`; parenthesise when you
  mean otherwise, e.g. `a <|> (b ~> f)`.
  """
  import Combinators

  # `<|>` — ordered choice, an alias for `Combinators.alt/1`. Bare strings are
  # lifted with `str/1` for convenience.
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

  @doc "Infix alias for `Combinators.map/2`: `parser ~> fun`."
  def parser ~> fun when is_function(parser) and is_function(fun), do: map(parser, fun)

  @doc "Infix alias for `Combinators.keep_right/2`: run both, keep the right result."
  def left ~>> right when is_function(left) and is_function(right), do: keep_right(left, right)

  @doc "Infix alias for `Combinators.keep_left/2`: run both, keep the left result."
  def left <<~ right when is_function(left) and is_function(right), do: keep_left(left, right)

  @doc "Alias for `Combinators.opt/1`."
  def optional(parser), do: opt(parser)

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
            {node, st2} -> {:cont, {[node | nodes], st2}}
            nil -> {:halt, :fail}
          end
        end)

      case result do
        :fail -> nil
        {nodes, st} -> {[:count | Enum.reverse(nodes)], st}
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
        {[:rep_range | Enum.reverse(nodes)], st}
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
      {node, st2} -> rep_range_collect(parser, st2, [node | nodes], count + 1, max)
      nil -> {nodes, state, count}
    end
  end

  @doc """
  Parse one or more `operand`s separated by `operator`, folding **left**.

  Unlike the tree-building combinators, `operand` is expected to yield a value
  and `operator` a two-argument function that combines the accumulated
  left-hand value with the next operand. This is the classic way to parse a
  left-associative infix operator (`1 - 2 - 3` == `(1 - 2) - 3`) without
  left recursion.
  """
  def chainl1(operand, operator) do
    fn state ->
      case operand.(state) do
        {left, st} -> chainl1_loop(left, operand, operator, st)
        nil -> nil
      end
    end
  end

  defp chainl1_loop(left, operand, operator, state) do
    case operator.(state) do
      {op_fun, st1} ->
        case operand.(st1) do
          {right, st2} -> chainl1_loop(op_fun.(left, right), operand, operator, st2)
          nil -> {left, state}
        end

      nil ->
        {left, state}
    end
  end

  @doc """
  Parse one or more `operand`s separated by `operator`, folding **right**
  (`2 ^ 3 ^ 2` == `2 ^ (3 ^ 2)`). Same operand/operator value convention as
  `chainl1/2`.
  """
  def chainr1(operand, operator) do
    fn state ->
      chainr1_parse(operand, operator, state)
    end
  end

  defp chainr1_parse(operand, operator, state) do
    case operand.(state) do
      {left, st1} ->
        case operator.(st1) do
          {op_fun, st2} ->
            case chainr1_parse(operand, operator, st2) do
              {right, st3} -> {op_fun.(left, right), st3}
              nil -> nil
            end

          nil ->
            {left, st1}
        end

      nil ->
        nil
    end
  end
end
