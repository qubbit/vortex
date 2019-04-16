defmodule ParserTest do
  use ExUnit.Case
  import Parser

  doctest Parser

  describe "integer combinator" do
    test "parses integer" do
      assert integer().(State.new("0"))
      assert integer().(State.new("123"))
      assert integer().(State.new("-123"))
    end
  end

  describe "parse" do
    test "parse integer" do
      assert parse("123", integer())
    end
  end
end
