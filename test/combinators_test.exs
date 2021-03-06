defmodule CombinatorTest do
  use ExUnit.Case
  import Combinators

  doctest Combinators

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

      assert {_, new_state} = hello.(input)
      assert world.(new_state)
    end
  end

  describe "char" do
    test "recognizes character by pattern" do
      input = State.new("7+8")
      digit = char("0-9")
      something_else = char("a")
      assert digit.(input)
      assert nil == something_else.(input)
    end

    test "recognizes character by pattern one after another" do
      input = State.new("7+8")
      digit = char("0-9")
      plus = char("+")
      assert {_, new_state} = digit.(input)
      assert plus.(new_state)
    end
  end

  describe "seq" do
    test "recognizes sequence of parsers" do
      input = State.new("7+8")
      addition = seq([char("1-9"), str("+"), char("0-9")])
      assert addition.(input)
    end
  end

  describe "rep" do
    test "recognizes positive integer number of repetitions" do
      input = State.new("vor7ex")
      repetition = rep(char("a-z"), 1)
      assert repetition.(input)
    end

    test "fails when minimum number of repetitions are not satisfied" do
      input = State.new("vor7ex")
      repetition = rep(char("a-z"), 4)
      assert nil == repetition.(input)
    end

    test "fails when starting string is empty and repetitions is not, with n > 0" do
      input = State.new("")
      repetition = rep(char(" "), 1)
      assert nil == repetition.(input)
    end

    test "recognizes zero repetitions" do
      input = State.new("")
      repetition = rep(char(" "), 0)
      assert repetition.(input)
    end

    test "recognizes one repetition" do
      input = State.new(" ")
      repetition = rep(char(" "), 1)
      assert repetition.(input)
    end
  end

  describe "alt" do
    test "recognizes alternatives" do
      input = State.new("2")
      alpha = char("a-z")
      digit = char("0-9")
      alts = alt([alpha, digit])
      assert alts.(input)
    end

    test "if non match returns nil" do
      input = State.new("hello world")
      alpha7 = char("a-g")
      digit = char("0-9")
      alts = alt([alpha7, digit])
      assert nil == alts.(input)
    end
  end

  describe "combination of fundamental combinators" do
    test "simple expression grammar" do
      ws = rep(str(" "), 0)
      natural_number = alt([str("0"), seq([char("1-9"), rep(char("0-9"), 0)])])
      addition = seq([natural_number, ws, str("+"), ws, natural_number])
      expression = alt([addition, natural_number])

      assert expression.(State.new("05"))
      assert expression.(State.new("50"))
      assert expression.(State.new("050"))
      assert expression.(State.new("5"))
      assert expression.(State.new("5+7"))
      assert expression.(State.new("5 + 7"))
      assert expression.(State.new("5   +  7"))
    end
  end
end
