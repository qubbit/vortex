defmodule OperatorsTest do
  @moduledoc """
  The infix operators are only sugar for named functions, so each test also
  checks the operator and the function agree.
  """
  use ExUnit.Case
  import Combinators
  import Combinators.Builtin

  defp run(parser, string), do: parser.(State.new(string))

  describe "<|> (choice, alias for alt)" do
    test "matches the first alternative that succeeds" do
      p = str("cat") <|> str("dog")
      assert {[:lit_str, "cat"], _} = run(p, "cat")
      assert {[:lit_str, "dog"], _} = run(p, "dog")
      assert nil == run(p, "fish")
    end

    test "agrees with alt/1" do
      assert run(str("a") <|> str("b"), "b") == run(alt([str("a"), str("b")]), "b")
    end

    test "lifts bare strings" do
      assert {_, _} = run("yes" <|> "no", "no")
    end
  end

  describe "~> (map)" do
    test "transforms the produced node" do
      p = char("a-z") ~> fn [_label, ch] -> String.upcase(ch) end
      assert {"A", _} = run(p, "abc")
    end

    test "agrees with map/2" do
      fun = fn node -> collect_text(node) end
      assert run(rep(char("0-9"), 1) ~> fun, "42") == run(map(rep(char("0-9"), 1), fun), "42")
    end

    test "propagates failure" do
      assert nil == run(char("0-9") ~> fn n -> n end, "x")
    end
  end

  describe "~>> (keep right) and <<~ (keep left)" do
    test "~>> keeps the right result" do
      p = str("(") ~>> str("x")
      assert {[:lit_str, "x"], state} = run(p, "(x")
      assert state.offset == 2
    end

    test "<<~ keeps the left result" do
      p = str("x") <<~ str(")")
      assert {[:lit_str, "x"], state} = run(p, "x)")
      assert state.offset == 2
    end

    test "chain to drop both delimiters" do
      p = str("(") ~>> str("x") <<~ str(")")
      assert {[:lit_str, "x"], _} = run(p, "(x)")
    end

    test "agree with keep_right/2 and keep_left/2" do
      assert run(str("a") ~>> str("b"), "ab") == run(keep_right(str("a"), str("b")), "ab")
      assert run(str("a") <<~ str("b"), "ab") == run(keep_left(str("a"), str("b")), "ab")
    end

    test "fail if either side fails" do
      assert nil == run(str("(") ~>> str("x"), "(y")
      assert nil == run(str("x") <<~ str(")"), "x]")
    end
  end

  describe "label/2 (the <?> idea)" do
    test "replaces low-level expectations when the parser fails at the start" do
      assert {:error, reason} = Parser.parse("!", label(rep(char("0-9"), 1), "a number"))
      assert reason == "line 1, column 1: expected a number"
    end

    test "does not hide an error found after input was consumed" do
      # "foo" matches, then "bar" fails deeper; the label must not mask that.
      grammar = label(seq([str("foo"), str("bar")]), "a greeting")
      assert {:error, reason} = Parser.parse("fooX", grammar)
      assert reason == ~s(line 1, column 4: expected "bar")
    end

    test "passes successful results through unchanged" do
      assert {[:rep | _], _} = run(label(rep(char("0-9"), 1), "a number"), "12")
    end
  end

  describe "choice/1 and optional/1 aliases" do
    test "choice is alt" do
      assert run(choice([str("a"), str("b")]), "b") == run(alt([str("a"), str("b")]), "b")
    end

    test "optional is opt" do
      assert {[:opt, []], _} = run(optional(str("x")), "y")
    end
  end
end
