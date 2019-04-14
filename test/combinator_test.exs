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
      refute world.(input)
    end
  end

  describe "chr" do
    test "recognizes character by pattern" do
      input = State.new("7+8")
      digit = chr("0-9")
      something_else = chr("a")
      assert digit.(input)
      refute something_else.(input)
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
    test "recognizes repetition" do
      input = State.new("vortex")
      repetition = rep(chr("a-z"), 6)
      assert x = repetition.(input)
      require IEx; IEx.pry()
    end
  end
end
