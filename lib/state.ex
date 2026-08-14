defmodule State do
  @moduledoc """
  Tracks position while traversing the input string.

  Besides the original `string` and a grapheme `offset` (plus `line`/`column`
  for diagnostics), the state carries `rest`: the still-unconsumed suffix of the
  input. Reading advances by slicing graphemes off the front of `rest` and
  re-pointing at the remainder with `binary_part/3`, so `peek/2`, `read/2` and
  `complete?/1` cost time proportional to how much is consumed — not to the
  absolute offset. That keeps a full parse linear in the length of the input
  rather than quadratic.
  """

  defstruct [:string, :rest, :offset, :line, :column]

  @type t :: %__MODULE__{
          string: binary,
          rest: binary,
          offset: non_neg_integer,
          line: pos_integer,
          column: non_neg_integer
        }

  @doc """
  Create and return a new `State` positioned at the start of `string`.
  """
  def new(string) do
    %State{string: string, rest: string, offset: 0, line: 1, column: 0}
  end

  @doc """
  Return up to the next `n` graphemes without consuming them.
  """
  def peek(%State{rest: rest}, n) do
    take_bytes(rest, n, 0)
  end

  @doc """
  Advance past the next `n` graphemes, updating the offset, line and column.
  """
  def read(%State{rest: rest, offset: o, line: l, column: c} = state, n) do
    consumed_bytes = grapheme_bytes(rest, n, 0)
    consumed = binary_part(rest, 0, consumed_bytes)
    new_rest = binary_part(rest, consumed_bytes, byte_size(rest) - consumed_bytes)

    {line_count, column_count} = count_lines(consumed, 0, 0)

    # A newline resets the column to the width of the trailing segment;
    # otherwise the consumed width is added to the current column.
    new_column = if line_count > 0, do: column_count, else: c + column_count

    %{state | rest: new_rest, offset: o + n, line: l + line_count, column: new_column}
  end

  # Take `n` graphemes off the front of `binary`.
  #
  # `String.slice/3` is O(byte_size(binary)) because it walks the whole string
  # to build a grapheme view, which made every read cost time proportional to
  # the *remaining* input and the overall parse quadratic. Walking exactly `n`
  # graphemes with `String.next_grapheme/1` is O(n) instead.
  defp take_bytes(binary, n, _acc) do
    binary_part(binary, 0, grapheme_bytes(binary, n, 0))
  end

  # Byte length of the first `n` graphemes of `binary` (or all of it if it has
  # fewer than `n`).
  defp grapheme_bytes(_binary, 0, acc), do: acc

  defp grapheme_bytes(binary, n, acc) do
    case String.next_grapheme(binary) do
      nil -> acc
      {g, rest} -> grapheme_bytes(rest, n - 1, acc + byte_size(g))
    end
  end

  # Count line breaks in `consumed` and the width of the trailing segment.
  #
  # Replaces `String.split(consumed, ~r/\R/)`, which compiled and ran a regex on
  # every single read. CRLF counts as one break, matching `\R`.
  defp count_lines(<<>>, lines, column), do: {lines, column}
  defp count_lines(<<"\r\n", rest::binary>>, lines, _column), do: count_lines(rest, lines + 1, 0)
  defp count_lines(<<"\n", rest::binary>>, lines, _column), do: count_lines(rest, lines + 1, 0)
  defp count_lines(<<"\r", rest::binary>>, lines, _column), do: count_lines(rest, lines + 1, 0)

  defp count_lines(binary, lines, column) do
    case String.next_grapheme(binary) do
      nil -> {lines, column}
      {_g, rest} -> count_lines(rest, lines, column + 1)
    end
  end

  @doc """
  Returns true when the whole input string has been consumed.
  """
  def complete?(%State{rest: ""}), do: true
  def complete?(%State{}), do: false
end
