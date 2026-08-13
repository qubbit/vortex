defmodule LexemeTest do
  @moduledoc """
  Tests for the whitespace layer: `ws`, `ws1`, `lexeme`, `symbol` and
  `whitespaced`.

  The convention under test is the standard one: a lexeme consumes the
  whitespace *after* itself, so a grammar only has to skip leading space once
  at the top level.
  """
  use ExUnit.Case
  import Combinators
  import Combinators.Builtin

  doctest Combinators.Builtin, import: true

  defp run(parser, string) do
    case parser.(State.new(string)) do
      {nodes, state} -> {nodes, state.rest}
      nil -> nil
    end
  end

  describe "ws" do
    test "consumes runs of whitespace" do
      assert {_, ""} = run(ws(), " \t\n\r")
    end

    test "succeeds without consuming when there is no whitespace" do
      assert {_, "abc"} = run(ws(), "abc")
    end

    test "succeeds on empty input" do
      assert {_, ""} = run(ws(), "")
    end

    # Elixir treats "\r\n" as a single grapheme, so `State.peek/2` returns it as
    # one unit and a plain `one_of/1` character-set test does not match it.
    test "consumes Windows CRLF line endings" do
      assert {_, "x"} = run(ws(), "\r\nx")
      assert {_, "x"} = run(ws(), " \r\n \r\n x")
    end

    test "consumes bare CR and bare LF" do
      assert {_, "x"} = run(ws(), "\rx")
      assert {_, "x"} = run(ws(), "\nx")
    end
  end

  describe "ws1" do
    test "requires at least one space" do
      assert {_, "abc"} = run(ws1(), "  abc")
    end

    test "accepts CRLF as the one required space" do
      assert {_, "abc"} = run(ws1(), "\r\nabc")
    end

    test "fails when no whitespace is present" do
      assert run(ws1(), "abc") == nil
    end
  end

  describe "lexeme" do
    test "consumes trailing whitespace after the parser" do
      assert {_, "b"} = run(lexeme(str("a")), "a   b")
    end

    test "succeeds with no trailing whitespace to consume" do
      assert {_, "b"} = run(lexeme(str("a")), "ab")
    end

    test "passes the wrapped parser's result through untouched" do
      {node, _} = run(lexeme(str("a")), "a ")
      {bare, _} = run(str("a"), "a")
      assert node == bare
    end

    test "does not consume leading whitespace" do
      assert run(lexeme(str("a")), "  a") == nil
    end

    test "fails when the wrapped parser fails" do
      assert run(lexeme(str("a")), "zzz") == nil
    end

    test "accepts a custom space consumer" do
      # A space consumer that also skips `#` comments to end of line.
      comment = seq([str("#"), rep(none_of("\n"), 0), opt(str("\n"))])
      space = rep(alt([one_of(" \t\n\r"), comment]), 0)

      assert {_, "b"} = run(lexeme(str("a"), space), "a # trailing\nb")
    end
  end

  describe "symbol" do
    test "matches a literal and eats trailing space" do
      assert {_, ""} = run(symbol("{"), "{  ")
    end

    test "fails when the literal does not match" do
      assert run(symbol("{"), "}") == nil
    end

    test "is equivalent to lexeme(str(token))" do
      assert run(symbol("+"), "+  x") == run(lexeme(str("+")), "+  x")
    end
  end

  describe "whitespaced" do
    test "skips leading whitespace before the parser" do
      assert {_, ""} = run(whitespaced(str("a")), "   a")
    end

    test "succeeds when there is no leading whitespace" do
      assert {_, ""} = run(whitespaced(str("a")), "a")
    end

    test "keeps the inner parser's result" do
      {node, _} = run(whitespaced(str("a")), "  a")
      {bare, _} = run(str("a"), "a")
      assert node == bare
    end
  end

  describe "composed grammar" do
    # A whitespace-insensitive grammar written with no manual `ws()` threading:
    # every token is a lexeme, and the top level is `whitespaced`.
    defp list_grammar do
      element = lexeme(rep(char("0-9"), 1))
      whitespaced(seq([symbol("["), sep_by(element, symbol(",")), symbol("]"), eof()]))
    end

    test "parses with whitespace scattered everywhere" do
      assert {_, ""} = run(list_grammar(), "  [ 1 , 2 ,3 ]  ")
    end

    test "parses with no whitespace at all" do
      assert {_, ""} = run(list_grammar(), "[1,2,3]")
    end

    test "parses across newlines" do
      assert {_, ""} = run(list_grammar(), "[\n  1,\n  2\n]\n")
    end

    test "still rejects malformed input" do
      assert run(list_grammar(), "[1,]") == nil
    end

    test "parses input using Windows CRLF line endings" do
      assert {_, ""} = run(list_grammar(), "[\r\n  1,\r\n  2\r\n]\r\n")
    end
  end

  describe "front-ends handle CRLF" do
    test "JSON parses a CRLF document" do
      assert {:ok, %{"a" => [1, 2]}} = JsonParser.parse("{\r\n  \"a\": [1,\r\n2]\r\n}")
    end

    test "calculator evaluates across CRLF" do
      assert {:ok, 9} = Calculator.eval("(1 +\r\n2) * 3")
    end

    test "LISP parses a CRLF program with comments" do
      assert {:ok, [{:list, [{:symbol, "+"}, {:number, 1}, {:number, 2}]}]} =
               LispParser.parse("; lead\r\n(+ 1 ; mid\r\n 2)\r\n")
    end
  end
end
