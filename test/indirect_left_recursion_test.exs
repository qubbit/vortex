defmodule IndirectLeftRecursionTest do
  @moduledoc """
  Pins down what `Combinators.LeftRec` does with **indirect** left recursion.

  `rule/2` implements the *direct* case of Warth et al.'s seed-growing
  algorithm: a rule that re-enters itself at the same offset returns the current
  seed, and the body is re-applied until it stops consuming more input. A cycle
  that passes through another rule (`a -> b -> a`) is not grown by that
  algorithm.

  The contract these tests lock in is a **safety** one, not a completeness one:

    * an indirect cycle always **terminates** — no infinite loop, no stack
      overflow, no hang;
    * it never returns a **wrong** answer — an input it cannot fully grow is
      reported as `{:error, _}`, not silently accepted as a partial parse;
    * the non-recursive base case always parses.

  These tests intentionally assert the *current, limited* behaviour so that
  extending `LeftRec` to the indirect case is a visible, deliberate change:
  several of them will start failing (with better results) if that support is
  added, which is the signal to update this file.

  See also `LeftRecursionTest` for the direct case, which grows fully.
  """
  use ExUnit.Case
  import Combinators
  import Combinators.Builtin

  defp num, do: text(rep(char("0-9"), 1)) ~> (&String.to_integer/1)

  # --- an alias cycle: a -> b -> a ----------------------------------------
  # a = b "+" num | num
  # b = a                      (b consumes nothing of its own)
  defp a do
    rule(:a, fn ->
      alt([
        seq([b(), str("+"), num()]) ~> fn [_, x, _, y] -> x + y end,
        num()
      ])
    end)
  end

  defp b, do: rule(:b, fn -> a() end)

  # --- a mutual cycle: x -> y -> x ----------------------------------------
  # x = y "+" num | num
  # y = x "-" num | num        (both sides can consume)
  defp x do
    rule(:x, fn ->
      alt([
        seq([y(), str("+"), num()]) ~> fn [_, p, _, q] -> p + q end,
        num()
      ])
    end)
  end

  defp y do
    rule(:y, fn ->
      alt([
        seq([x(), str("-"), num()]) ~> fn [_, p, _, q] -> p - q end,
        num()
      ])
    end)
  end

  # --- a three-rule cycle: p -> q -> r -> p --------------------------------
  defp p do
    rule(:p, fn ->
      alt([
        seq([q(), str("+"), num()]) ~> fn [_, m, _, n] -> m + n end,
        num()
      ])
    end)
  end

  defp q, do: rule(:q, fn -> r() end)
  defp r, do: rule(:r, fn -> p() end)

  # Run a parser under a timeout so a hypothetical infinite loop fails the test
  # instead of hanging the suite.
  defp parse_within(input, parser, timeout \\ 5_000) do
    task = Task.async(fn -> Parser.parse(input, parser) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> flunk("parse of #{inspect(input)} did not terminate within #{timeout}ms")
    end
  end

  # True for any well-formed parse outcome — used where the assertion is
  # "it came back with *something*" rather than a particular result.
  defp settled?({:ok, _}), do: true
  defp settled?({:error, _}), do: true
  defp settled?(_), do: false

  describe "termination (the safety guarantee)" do
    test "an alias cycle terminates instead of looping forever" do
      assert {:ok, 7} = parse_within("7", a())
      assert {:error, _} = parse_within("1+2", a())
    end

    test "a mutual cycle terminates" do
      assert {:ok, 5} = parse_within("5", x())
      assert {:error, _} = parse_within("1-2+3", x())
    end

    test "a three-rule cycle terminates" do
      assert {:ok, 5} = parse_within("5", p())
      assert {:error, _} = parse_within("1+2", p())
    end

    test "longer inputs still terminate rather than degrading into a hang" do
      for input <- ["1+2+3", "1+2+3+4+5", "1-2+3-4+5-6"] do
        # The point is that a result comes back at all; either outcome is fine.
        assert parse_within(input, a()) |> settled?()
        assert parse_within(input, x()) |> settled?()
      end
    end
  end

  describe "the base case always works" do
    test "a rule in an indirect cycle still parses its non-recursive branch" do
      assert {:ok, 0} = parse_within("0", a())
      assert {:ok, 42} = parse_within("42", a())
      assert {:ok, 123} = parse_within("123", x())
      assert {:ok, 9} = parse_within("9", p())
    end
  end

  describe "current limits (these assert what is NOT yet supported)" do
    # An alias cycle plants a seed that consumes nothing, so the recursive
    # branch can never extend past the base case.
    test "an alias cycle does not grow beyond the base case" do
      assert {:error, _} = parse_within("1+2", a())
    end

    # A mutual cycle grows exactly one level: parsing `x` seeds `y`, which lets
    # the `y "+" num` branch fire once, but no further.
    test "a mutual cycle grows exactly one level, then stops" do
      assert {:ok, 3} = parse_within("1+2", x())
      assert {:error, _} = parse_within("1-2+3", x())
    end

    test "a three-rule cycle does not grow" do
      assert {:error, _} = parse_within("1+2", p())
    end
  end

  describe "no wrong answers" do
    # The important half of the guarantee: when growth is incomplete the parser
    # reports an error rather than accepting a prefix and discarding the rest.
    test "an ungrowable input is an error, not a silently partial parse" do
      assert {:error, reason} = parse_within("1+2", a())
      assert reason =~ "line 1"
    end

    # An abandoned seed from a cycle that failed to grow must not be left behind
    # for the next grammar. These run in this test's process on purpose: the
    # memo/seed tables live in the process dictionary, so using `parse_within/3`
    # would give each parse a fresh Task dictionary and prove nothing.
    test "a failed cycle leaves no seed behind for a later grammar" do
      # Fails partway through growing :a, then :x and :p reuse the tables.
      assert {:error, _} = Parser.parse("1+2", a())
      assert {:ok, 3} = Parser.parse("1+2", x())
      assert {:error, _} = Parser.parse("1+2", p())

      # The *directly* left-recursive grammars must be unaffected too.
      assert {:ok, 7} = Parser.parse("7", a())
      assert {:error, _} = Parser.parse("1+2", a())
    end
  end
end
