defmodule CombinatorTest do
  use ExUnit.Case
  import Combinator

  doctest Combinator

  describe "str" do
    test "recognizes simple strings" do
      input = State.new("hello world")
      hello = str("hello")
      world = str("world")

      assert hello.(input)
      assert nil == world.(input)
    end

    test "recognizes strings one after another" do
      input = State.new("hello world")
      hello = str("hello")
      world = str(" world")

      assert [_, new_state] = hello.(input)
      assert world.(new_state)
    end
  end

  describe "chr" do
    test "recognizes character by pattern" do
      input = State.new("7+8")
      digit = chr("0-9")
      something_else = chr("a")
      assert digit.(input)
      assert nil == something_else.(input)
    end

    test "recognizes character by pattern one after another" do
      input = State.new("7+8")
      digit = chr("0-9")
      plus = chr("+")
      assert [_, new_state] = digit.(input)
      assert plus.(new_state)
    end
  end

  describe "seq" do
    test "recognizes sequence of parsers" do
      input = State.new("7+8")
      addition = seq([chr("1-9"), str("+"), chr("0-9")])
      assert addition.(input)
    end
  end

  describe "rep" do
    test "recognizes positive integer number of repetitions" do
      input = State.new("vor7ex")
      repetition = rep(chr("a-z"), 1)
      assert repetition.(input)
    end

    test "fails when minimum number of repetitions are not satisfied" do
      input = State.new("vor7ex")
      repetition = rep(chr("a-z"), 4)
      assert nil == repetition.(input)
    end

    test "fails when starting string is empty and repetitions is not, with n > 0" do
      input = State.new("")
      repetition = rep(chr(" "), 1)
      assert nil == repetition.(input)
    end

    test "recognizes zero repetitions" do
      input = State.new("")
      repetition = rep(chr(" "), 0)
      assert repetition.(input)
    end

    test "recognizes one repetition" do
      input = State.new(" ")
      repetition = rep(chr(" "), 1)
      assert repetition.(input)
    end
  end

  describe "alt" do
    test "recognizes alternatives" do
      input = State.new("2")
      alpha = chr("a-z")
      digit = chr("0-9")
      alts = alt([alpha, digit])
      assert alts.(input)
    end
  end
end
