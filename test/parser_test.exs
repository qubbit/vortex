defmodule ParserTest do
  use ExUnit.Case
  import Parser
  import Combinators.Builtin

  describe "integer combinator" do
    test "parses integer" do
      assert integer().(State.new("0"))
      assert integer().(State.new("123"))
      assert integer().(State.new("-123"))
    end

    test "parses single-digit integers" do
      assert {_nodes, state} = integer().(State.new("7"))
      assert State.complete?(state)
      assert {_nodes, neg} = integer().(State.new("-4"))
      assert State.complete?(neg)
    end
  end

  describe "parse" do
    test "parse integer" do
      assert parse("123", integer())
    end

    test "returns {:ok, nodes} when the grammar consumes the whole input" do
      assert {:ok, nodes} = parse("123", integer())
      assert is_list(nodes)
    end

    test "returns {:error, _} when nothing matches at offset 0" do
      assert {:error, reason} = parse("abc", integer())
      assert reason =~ "offset 0"
    end

    test "returns {:error, _} on a partial (non-consuming) parse" do
      assert {:error, reason} = parse("123rest", integer())
      assert reason =~ "unexpected input"
      assert reason =~ "offset 3"
    end

    test "reports the offset where a partial parse stopped" do
      assert {:error, reason} = parse("-42tail", integer())
      assert reason =~ "offset 3"
    end
  end
end
