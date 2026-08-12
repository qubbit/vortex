defmodule ParserErrorsTest do
  use ExUnit.Case
  import Combinators
  import Combinators.Builtin

  describe "furthest-failure reporting" do
    test "names the expected literal at the failure position" do
      assert {:error, reason} = Parser.parse("cat", str("dog"))
      assert reason == ~s(line 1, column 1: expected "dog")
    end

    test "reports the deepest point reached, not the first alternative tried" do
      grammar = seq([str("foo"), str("bar")])
      assert {:error, reason} = Parser.parse("fooX", grammar)
      # "foo" matched; the failure is at column 4 where "bar" was expected.
      assert reason == ~s(line 1, column 4: expected "bar")
    end

    test "accumulates alternatives expected at the same position" do
      grammar = alt([str("cat"), str("dog")])
      assert {:error, reason} = Parser.parse("bird", grammar)
      assert reason =~ "line 1, column 1"
      assert reason =~ ~s("cat")
      assert reason =~ ~s("dog")
    end

    test "tracks line and column across newlines" do
      grammar = seq([str("a"), str("\n"), str("b"), str("c")])
      assert {:error, reason} = Parser.parse("a\nbX", grammar)
      assert reason == ~s(line 2, column 2: expected "c")
    end

    test "char failures describe the character class" do
      assert {:error, reason} = Parser.parse("x", char("0-9"))
      assert reason == "line 1, column 1: expected a character in [0-9]"
    end
  end

  describe "eof" do
    test "succeeds at the end of input" do
      assert {:ok, _} = Parser.parse("ab", seq([str("ab"), eof()]))
    end

    test "forces a grammar to consume everything" do
      assert {:error, reason} = Parser.parse("abXX", seq([str("ab"), eof()]))
      assert reason =~ "expected end of input"
    end
  end

  describe "lookahead" do
    test "followed_by matches without consuming" do
      grammar = seq([followed_by(str("ab")), str("a")])
      assert {[:seq, [:followed_by, []], [:lit_str, "a"]], state} = grammar.(State.new("ab"))
      assert state.offset == 1
    end

    test "followed_by fails when the lookahead would not match" do
      assert nil == followed_by(str("ab")).(State.new("xy"))
    end

    test "not_followed_by matches only when the lookahead fails" do
      assert {[:not_followed_by, []], state} = not_followed_by(str("ab")).(State.new("xy"))
      assert state.offset == 0
      assert nil == not_followed_by(str("ab")).(State.new("ab"))
    end
  end

  describe "count" do
    test "matches exactly n occurrences" do
      assert {_nodes, state} = count(3, char("0-9")).(State.new("123x"))
      assert state.offset == 3
    end

    test "fails with fewer than n occurrences" do
      assert nil == count(3, char("0-9")).(State.new("12x"))
    end

    test "count of zero consumes nothing" do
      assert {_nodes, state} = count(0, char("0-9")).(State.new("abc"))
      assert state.offset == 0
    end
  end

  describe "rep_range" do
    test "matches between min and max, greedily" do
      assert {_nodes, state} = rep_range(char("0-9"), 1, 2).(State.new("123"))
      assert state.offset == 2
    end

    test "requires at least min" do
      assert nil == rep_range(char("0-9"), 2, 4).(State.new("1x"))
    end

    test "succeeds at min when max is not reached" do
      assert {_nodes, state} = rep_range(char("0-9"), 0, 5).(State.new("ab"))
      assert state.offset == 0
    end
  end
end
