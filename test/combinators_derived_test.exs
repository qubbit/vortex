defmodule CombinatorsDerivedTest do
  @moduledoc """
  Tests for the combinators that were finished off in `Combinators` and
  `Combinators.Builtin`: `any`, `map`, `lazy`, `many`, `many1`, `sep_by`,
  `sep_by1`, `choice`, `between`, `one_of` and `none_of`.
  """
  use ExUnit.Case
  import Combinators
  import Combinators.Builtin

  # Run a parser against a raw string, returning `{nodes, remaining_string}` or
  # `nil` so assertions can talk about what was consumed.
  defp run(parser, string) do
    case parser.(State.new(string)) do
      {nodes, state} -> {nodes, state.rest}
      nil -> nil
    end
  end

  describe "any" do
    test "consumes a single character" do
      assert {[:any, "h"], "i"} = run(any(), "hi")
    end

    test "fails at end of input" do
      assert nil == run(any(), "")
    end
  end

  describe "one_of" do
    test "matches a character in the set" do
      assert {[:one_of, "+"], "1"} = run(one_of("+-*/"), "+1")
    end

    test "fails when the character is not in the set" do
      assert nil == run(one_of("+-*/"), "a1")
    end

    test "fails at end of input" do
      assert nil == run(one_of("+-*/"), "")
    end

    test "treats set characters literally, not as a regex" do
      assert {[:one_of, "."], ""} = run(one_of(".^$"), ".")
    end
  end

  describe "none_of" do
    test "matches a character outside the set" do
      assert {[:none_of, "a"], "b"} = run(none_of("\"\\"), "ab")
    end

    test "fails when the character is in the set" do
      assert nil == run(none_of("\"\\"), "\"x")
    end

    test "fails at end of input" do
      assert nil == run(none_of("x"), "")
    end
  end

  describe "many" do
    test "matches zero occurrences and consumes nothing" do
      assert {_nodes, "abc"} = run(many(char("0-9")), "abc")
    end

    test "matches several occurrences greedily" do
      assert {_nodes, "x"} = run(many(char("0-9")), "123x")
    end
  end

  describe "many1" do
    test "requires at least one occurrence" do
      assert nil == run(many1(char("0-9")), "abc")
    end

    test "matches one or more occurrences" do
      assert {_nodes, ""} = run(many1(char("0-9")), "42")
    end
  end

  describe "alt (a.k.a. the choice do-block)" do
    test "succeeds with the first matching alternative" do
      p = alt([char("a-c"), char("0-9")])
      assert {[:char, "b"], ""} = run(p, "b")
      assert {[:char, "7"], ""} = run(p, "7")
    end

    test "fails when no alternative matches" do
      assert nil == run(alt([char("a-c"), char("0-9")]), "z")
    end
  end

  describe "keyword_alt" do
    defp keywords do
      keyword_alt([
        {["i"], str("if")},
        {["w"], str("while")},
        {["f"], str("for")},
        {["f"], str("function")}
      ])
    end

    test "dispatches to the alternative for the leading character" do
      assert {[:lit_str, "if"], ""} = run(keywords(), "if")
      assert {[:lit_str, "while"], ""} = run(keywords(), "while")
    end

    test "keeps the original order within a bucket" do
      # `for` and `function` share the "f" bucket; both must still match.
      assert {[:lit_str, "for"], ""} = run(keywords(), "for")
      assert {[:lit_str, "function"], ""} = run(keywords(), "function")
    end

    test "fails when the leading character has no alternatives" do
      assert nil == run(keywords(), "zzz")
    end

    test "fails when the bucket matches no alternative" do
      assert nil == run(keywords(), "fizz")
    end

    test "fails on empty input" do
      assert nil == run(keywords(), "")
    end

    test "produces the same results as the equivalent alt/1" do
      plain = alt([str("if"), str("while"), str("for"), str("function")])

      for input <- ["if", "while", "for", "function", "zzz", "fizz", ""] do
        assert run(keywords(), input) == run(plain, input),
               "disagreed on #{inspect(input)}"
      end
    end

    test "fallbacks run when no character-specific alternative matches" do
      p = keyword_alt([{["i"], str("if")}], [many1(char("0-9"))])
      assert {[:lit_str, "if"], ""} = run(p, "if")
      assert {_digits, ""} = run(p, "123")
      assert nil == run(p, "zz")
    end

    test "fallbacks run after a failed bucket, not instead of it" do
      # "i" dispatches to `if`; when that fails the fallback still gets a turn.
      p = keyword_alt([{["i"], str("if")}], [str("igloo")])
      assert {[:lit_str, "if"], ""} = run(p, "if")
      assert {[:lit_str, "igloo"], ""} = run(p, "igloo")
    end
  end

  describe "between" do
    test "matches an inner parser wrapped by delimiters" do
      p = between(str("("), str(")"), many1(char("0-9")))
      assert {_nodes, ""} = run(p, "(123)")
    end

    test "fails when a delimiter is missing" do
      p = between(str("("), str(")"), many1(char("0-9")))
      assert nil == run(p, "(123")
    end
  end

  describe "sep_by1" do
    test "matches a single element with no separator" do
      assert {_nodes, ""} = run(sep_by1(char("0-9"), str(",")), "5")
    end

    test "matches several separated elements" do
      assert {_nodes, ""} = run(sep_by1(char("0-9"), str(",")), "1,2,3")
    end

    test "fails on an empty input" do
      assert nil == run(sep_by1(char("0-9"), str(",")), "")
    end
  end

  describe "sep_by" do
    test "succeeds on empty input without consuming" do
      assert {_nodes, "xyz"} = run(sep_by(char("0-9"), str(",")), "xyz")
    end

    test "matches separated elements when present" do
      assert {_nodes, "!"} = run(sep_by(char("0-9"), str(",")), "1,2!")
    end
  end

  describe "map" do
    test "transforms the produced node on success" do
      upcase = map(char("a-z"), fn [_label, ch] -> String.upcase(ch) end)
      assert {"A", ""} = run(upcase, "a")
    end

    test "propagates failure untouched" do
      upcase = map(char("a-z"), fn node -> node end)
      assert nil == run(upcase, "1")
    end
  end

  describe "lazy" do
    test "defers construction, enabling self-recursive grammars" do
      # nested = "(" nested? ")" — impossible to build without lazy/1 because
      # the rule refers to itself.
      defmodule Nested do
        import Combinators

        def parens do
          seq([str("("), opt(lazy(&parens/0)), str(")")])
        end
      end

      assert {_nodes, state} = Nested.parens().(State.new("((()))"))
      assert State.complete?(state)
      assert nil == Nested.parens().(State.new("(()"))
    end
  end
end
