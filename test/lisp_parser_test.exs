defmodule LispParserTest do
  use ExUnit.Case
  doctest LispParser

  describe "atoms: numbers" do
    test "parses a positive integer" do
      assert {:ok, [{:number, 42}]} = LispParser.parse("42")
    end

    test "parses a negative integer" do
      assert {:ok, [{:number, -7}]} = LispParser.parse("-7")
    end

    test "parses an explicitly positive integer" do
      assert {:ok, [{:number, 3}]} = LispParser.parse("+3")
    end

    test "parses a float" do
      assert {:ok, [{:number, 3.14}]} = LispParser.parse("3.14")
    end

    test "parses a negative float" do
      assert {:ok, [{:number, -0.5}]} = LispParser.parse("-0.5")
    end

    test "a bare sign is a symbol, not a number" do
      assert {:ok, [{:symbol, "-"}]} = LispParser.parse("-")
      assert {:ok, [{:symbol, "+"}]} = LispParser.parse("+")
    end
  end

  describe "atoms: symbols" do
    test "parses an alphabetic symbol" do
      assert {:ok, [{:symbol, "foo"}]} = LispParser.parse("foo")
    end

    test "parses symbols containing punctuation" do
      assert {:ok, [{:symbol, "hello-world?"}]} = LispParser.parse("hello-world?")
      assert {:ok, [{:symbol, "<="}]} = LispParser.parse("<=")
      assert {:ok, [{:symbol, "set!"}]} = LispParser.parse("set!")
    end
  end

  describe "atoms: booleans" do
    test "parses true" do
      assert {:ok, [{:bool, true}]} = LispParser.parse("#t")
    end

    test "parses false" do
      assert {:ok, [{:bool, false}]} = LispParser.parse("#f")
    end
  end

  describe "atoms: strings" do
    # ~S[...] is used for LISP source so backslashes stay literal, i.e. the
    # bytes the parser actually sees. Expected values use ordinary strings.
    test "parses a simple string" do
      assert {:ok, [{:string, "a string"}]} = LispParser.parse(~S["a string"])
    end

    test "parses an empty string" do
      assert {:ok, [{:string, ""}]} = LispParser.parse(~S[""])
    end

    test "unescapes quotes, backslashes and control escapes" do
      assert {:ok, [{:string, ~s(he said "hi")}]} = LispParser.parse(~S["he said \"hi\""])
      assert {:ok, [{:string, "back\\slash"}]} = LispParser.parse(~S["back\\slash"])
      assert {:ok, [{:string, "line1\nline2"}]} = LispParser.parse(~S["line1\nline2"])
      assert {:ok, [{:string, "a\tb"}]} = LispParser.parse(~S["a\tb"])
    end

    test "keeps parentheses and whitespace inside strings literal" do
      assert {:ok, [{:string, "(not a list) "}]} = LispParser.parse(~S["(not a list) "])
    end
  end

  describe "lists" do
    test "parses the empty list" do
      assert {:ok, [{:list, []}]} = LispParser.parse("()")
    end

    test "parses a flat list" do
      assert {:ok, [{:list, [{:number, 1}, {:number, 2}, {:number, 3}]}]} =
               LispParser.parse("(1 2 3)")
    end

    test "ignores surrounding and interior whitespace" do
      assert {:ok, [{:list, [{:number, 1}, {:number, 2}]}]} = LispParser.parse("(  1   2 )")
    end

    test "parses a nested list" do
      assert {:ok, [{:list, [{:symbol, "+"}, {:number, 1}, {:list, [{:symbol, "*"}, {:number, 2}, {:number, 3}]}]}]} =
               LispParser.parse("(+ 1 (* 2 3))")
    end

    test "does not require whitespace between an atom and a parenthesis" do
      assert {:ok, [{:list, [{:symbol, "a"}, {:list, [{:symbol, "b"}]}, {:symbol, "c"}]}]} =
               LispParser.parse("(a(b)c)")
    end

    test "parses across multiple lines" do
      source = """
      (define (square x)
        (* x x))
      """

      assert {:ok, [{:list, [{:symbol, "define"} | _rest]}]} = LispParser.parse(source)
    end
  end

  describe "quote" do
    test "quotes a symbol" do
      assert {:ok, [{:quote, {:symbol, "foo"}}]} = LispParser.parse("'foo")
    end

    test "quotes a list" do
      assert {:ok, [{:quote, {:list, [{:number, 1}, {:number, 2}]}}]} = LispParser.parse("'(1 2)")
    end

    test "allows whitespace after the quote mark" do
      assert {:ok, [{:quote, {:symbol, "x"}}]} = LispParser.parse("' x")
    end
  end

  describe "programs with multiple top-level forms" do
    test "parses several forms in a row" do
      assert {:ok, [{:number, 1}, {:number, 2}, {:number, 3}]} = LispParser.parse("1 2 3")
    end

    test "parses a realistic program" do
      source = """
      (define pi 3.14159)
      (define (area r) (* pi r r))
      (area 10)
      """

      assert {:ok, forms} = LispParser.parse(source)
      assert length(forms) == 3
    end
  end

  describe "comments" do
    test "skips a full-line comment" do
      assert {:ok, [{:list, [{:symbol, "+"}, {:number, 1}, {:number, 2}]}]} =
               LispParser.parse("; add one and two\n(+ 1 2)")
    end

    test "skips a trailing comment" do
      assert {:ok, [{:number, 1}, {:number, 2}]} = LispParser.parse("1 ; one\n2 ; two")
    end

    test "skips a comment inside a list" do
      assert {:ok, [{:list, [{:symbol, "a"}, {:symbol, "b"}]}]} =
               LispParser.parse("(a ; the first\n b)")
    end

    test "an input that is only a comment parses to no forms" do
      assert {:ok, []} = LispParser.parse("; nothing here")
    end
  end

  describe "empty and whitespace-only input" do
    test "empty string yields no forms" do
      assert {:ok, []} = LispParser.parse("")
    end

    test "whitespace-only string yields no forms" do
      assert {:ok, []} = LispParser.parse("   \n\t  ")
    end
  end

  describe "errors" do
    test "an unclosed list fails" do
      assert {:error, _} = LispParser.parse("(1 2")
    end

    test "a stray closing parenthesis fails" do
      assert {:error, _} = LispParser.parse(")")
    end

    test "an unterminated string fails" do
      assert {:error, _} = LispParser.parse(~s["no end])
    end

    test "an unmatched opening parenthesis fails" do
      assert {:error, _} = LispParser.parse("(")
    end
  end

  describe "parse_one/1" do
    test "returns a single form directly" do
      assert {:ok, {:list, [{:symbol, "+"}, {:number, 1}, {:number, 2}]}} =
               LispParser.parse_one("(+ 1 2)")
    end

    test "rejects input with more than one form" do
      assert {:error, reason} = LispParser.parse_one("1 2")
      assert reason =~ "found 2"
    end

    test "rejects empty input" do
      assert {:error, reason} = LispParser.parse_one("")
      assert reason =~ "none"
    end

    test "propagates parse errors" do
      assert {:error, _} = LispParser.parse_one("(1")
    end
  end

  describe "parse!/1" do
    test "returns forms on success" do
      assert [{:number, 1}, {:number, 2}] = LispParser.parse!("1 2")
    end

    test "raises on a parse error" do
      assert_raise ArgumentError, ~r/invalid LISP/, fn -> LispParser.parse!("(") end
    end
  end
end
