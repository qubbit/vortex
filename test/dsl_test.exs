defmodule DSLTest do
  use ExUnit.Case
  import Combinators
  import Combinators.Builtin
  import Combinators.DSL

  defp ident, do: text(rep(char("a-z"), 1))
  defp number, do: text(rep(char("0-9"), 1)) ~> (&String.to_integer/1)

  describe "sequence" do
    test "binds results and returns a value" do
      pair =
        sequence do
          k <- ident()
          _ <- str(":")
          v <- ident()
          return {k, v}
        end

      assert {:ok, {"foo", "bar"}} = Parser.parse("foo:bar", pair)
    end

    test "non-binding lines run and are discarded" do
      p =
        sequence do
          str("(")
          n <- number()
          str(")")
          return n
        end

      assert {:ok, 42} = Parser.parse("(42)", p)
    end

    test "fails (and reports) if any step fails" do
      p =
        sequence do
          _ <- str("[")
          n <- number()
          _ <- str("]")
          return n
        end

      assert {:error, reason} = Parser.parse("[42)", p)
      assert reason =~ "column 4"
      assert reason =~ ~s("]")
    end

    test "the bound pattern can destructure a node" do
      p =
        sequence do
          [_seq, [_, a], [_, b]] <- seq([char("0-9"), char("0-9")])
          return a <> b
        end

      assert {:ok, "12"} = Parser.parse("12", p)
    end

    test "a single trailing parser works with no binds" do
      p =
        sequence do
          return 99
        end

      assert {:ok, 99} = Parser.parse("", p)
    end
  end

  describe "choice" do
    test "matches the first alternative that succeeds" do
      yn =
        choice do
          str("yes")
          str("no")
        end

      assert {:ok, [:lit_str, "yes"]} = Parser.parse("yes", yn)
      assert {:ok, [:lit_str, "no"]} = Parser.parse("no", yn)
    end

    test "reports all alternatives on failure" do
      yn =
        choice do
          str("yes")
          str("no")
        end

      assert {:error, reason} = Parser.parse("maybe", yn)
      assert reason =~ ~s("yes")
      assert reason =~ ~s("no")
    end

    test "is equivalent to alt/1" do
      via_macro =
        choice do
          char("a-c")
          char("0-9")
        end

      via_alt = alt([char("a-c"), char("0-9")])
      assert Parser.parse("7", via_macro) == Parser.parse("7", via_alt)
    end
  end

  describe "sequence and choice together" do
    # A tiny grammar: term = number | "(" term ")"
    defp term do
      choice do
        number()
        sequence do
          _ <- str("(")
          t <- lazy(&term/0)
          _ <- str(")")
          return t
        end
      end
    end

    test "nest cleanly" do
      assert {:ok, 5} = Parser.parse("5", term())
      assert {:ok, 5} = Parser.parse("(((5)))", term())
    end
  end
end
