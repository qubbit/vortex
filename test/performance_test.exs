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

  # `State.read/2` used `String.slice(rest, 0, n)`, which walks the whole
  # binary to build a grapheme view. That made a single read cost time
  # proportional to the *remaining* input, so any parse was quadratic overall —
  # invisible in the tests above, which read from near the end of the input.
  #
  # Reading one grapheme must cost the same whether 1KB or 200KB remains.
  test "reading a single grapheme is independent of the remaining input size" do
    time_reads = fn size ->
      state = State.new(String.duplicate("a", size))

      {micros, _} =
        :timer.tc(fn ->
          Enum.reduce(1..2_000, state, fn _, s -> State.read(s, 1) end)
        end)

      micros
    end

    small = time_reads.(1_000)
    large = time_reads.(200_000)

    # Allow generous headroom for scheduling noise; the old implementation was
    # ~200x slower on the large input, so anything near-constant passes.
    assert large < max(small, 1_000) * 20,
           "reading from a 200KB input took #{large}us vs #{small}us from 1KB — " <>
             "State.read looks O(remaining) again"
  end

  describe "State.next/1" do
    test "returns the grapheme and the advanced state" do
      assert {"a", state} = State.next(State.new("abc"))
      assert state.rest == "bc"
      assert state.offset == 1
      assert state.column == 1
    end

    test "returns nil at the end of the input" do
      assert State.next(State.new("")) == nil
    end

    test "treats CRLF as a single grapheme and one line break" do
      assert {"\r\n", state} = State.next(State.new("\r\nx"))
      assert state.line == 2
      assert state.column == 0
      assert state.rest == "x"
    end

    test "agrees with peek/2 plus read/2" do
      for input <- ["abc", "\n", "\r\n", "héllo", "😀x"] do
        state = State.new(input)
        assert {grapheme, advanced} = State.next(state)
        assert grapheme == State.peek(state, 1)
        read = State.read(state, 1)
        assert advanced.rest == read.rest
        assert advanced.offset == read.offset
        assert advanced.line == read.line
        assert advanced.column == read.column
      end
    end
  end

  test "line and column tracking survives the fast path" do
    state = State.new("ab\ncd\r\nef")

    after_first = State.read(state, 3)
    assert after_first.line == 2
    assert after_first.column == 0

    # Consumes "c", "d", the CRLF (one grapheme, one line break), then "e" —
    # so the column is 1, counting the "e" on the new line.
    after_second = State.read(after_first, 4)
    assert after_second.line == 3
    assert after_second.column == 1
    assert after_second.rest == "f"
  end
end
