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
    String.slice(rest, 0, n)
  end

  @doc """
  Advance past the next `n` graphemes, updating the offset, line and column.
  """
  def read(%State{rest: rest, offset: o, line: l, column: c} = state, n) do
    consumed = String.slice(rest, 0, n)
    consumed_bytes = byte_size(consumed)
    new_rest = binary_part(rest, consumed_bytes, byte_size(rest) - consumed_bytes)

    lines = String.split(consumed, ~r/\R/)
    line_count = Enum.count(lines) - 1
    column_count = lines |> List.last() |> String.length()

    # A newline resets the column to the width of the trailing segment;
    # otherwise the consumed width is added to the current column.
    new_column = if line_count > 0, do: column_count, else: c + column_count

    %{state | rest: new_rest, offset: o + n, line: l + line_count, column: new_column}
  end

  @doc """
  Returns true when the whole input string has been consumed.
  """
  def complete?(%State{rest: ""}), do: true
  def complete?(%State{}), do: false
end
