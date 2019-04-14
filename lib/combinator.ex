defmodule Combinator do
  def str(string) do
    fn state ->
      len = String.length(string)
      chunk = State.peek(state, len)

      if chunk == string do
        [[:str, chunk], State.read(state, len)]
      end
    end
  end

  def chr(pattern) do
    fn state ->
      chunk = State.peek(state, 1)

      if chunk =~ ~r{[#{pattern}]} do
        [[:chr, chunk], State.read(state, 1)]
      end
    end
  end

  def seq(parsers) do
    fn state ->
      result = Enum.reduce(parsers, {[], state}, fn parser, acc ->
        {acc_nodes, acc_state} = acc
        [node, new_state] = parser.(acc_state)
        {acc_nodes ++ [node], new_state}
      end)

      {nodes, new_state} = result

      if new_state do
        [[:seq | nodes], new_state]
      end
    end
  end

  def rep(parser, n) do
    fn state ->
      result = Enum.reduce(1..n, {[], state}, fn _, acc ->
        {acc_nodes, acc_state} = acc
        [node, new_state] = parser.(acc_state)
        {acc_nodes ++ [node], new_state}
      end)

      {nodes, new_state} = result

      if new_state do
        [[:rep | nodes], new_state]
      end
    end
  end
end
