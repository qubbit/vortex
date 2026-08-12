defmodule PerformanceTest do
  @moduledoc """
  These parse deliberately large inputs. Beyond checking correctness, they act
  as a guard against reintroducing quadratic node accumulation: under an
  O(n^2) `seq`/`rep` the 20k-element cases would take seconds, so the suite
  simply completing quickly is part of the signal.
  """
  use ExUnit.Case
  import Combinators

  test "rep over a large input keeps every match in order" do
    n = 20_000
    input = String.duplicate("7", n)
    assert {[:rep | nodes], state} = rep(char("0-9"), 0).(State.new(input))
    assert length(nodes) == n
    assert State.complete?(state)
  end

  test "a very long seq succeeds and preserves order" do
    n = 20_000
    input = String.duplicate("a", n)
    grammar = seq(List.duplicate(str("a"), n))
    assert {[:seq | nodes], state} = grammar.(State.new(input))
    assert length(nodes) == n
    assert State.complete?(state)
  end

  test "the LISP reader parses a large flat list" do
    n = 10_000
    program = "(" <> Enum.map_join(1..n, " ", &Integer.to_string/1) <> ")"
    assert {:ok, [{:list, elements}]} = LispParser.parse(program)
    assert length(elements) == n
    assert {:number, 1} = hd(elements)
    assert {:number, ^n} = List.last(elements)
  end
end
