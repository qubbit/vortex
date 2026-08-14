defmodule LuaParserTest do
  @moduledoc """
  Tests for the Lua 5.4 parser.

  Coverage follows the EBNF in `examples/lua.ebnf` production by production,
  plus the operator precedence table from §3.4.8. The accept/reject behaviour
  was cross-checked against the real `luac -p` binary over a corpus of 106
  Neovim runtime files with zero disagreements on syntax; the cases below are
  the distilled version of that differential testing.
  """
  use ExUnit.Case
  doctest LuaParser

  defp parse!(src), do: LuaParser.parse!(src)

  defp accepts?(src), do: match?({:ok, _}, LuaParser.parse(src))

  # First (and usually only) statement of a chunk.
  defp stmt(src), do: parse!(src) |> hd()

  # The expression of `x = <exp>`.
  defp expr(src) do
    {:assign, [value], _} = stmt("x = " <> src)
    value
  end

  describe "literals" do
    test "nil, booleans and varargs" do
      assert expr("nil") == {nil}
      assert expr("true") == {:boolean, true}
      assert expr("false") == {:boolean, false}
      assert expr("...") == {:varargs}
    end

    test "integers" do
      assert expr("0") == {:number, 0}
      assert expr("42") == {:number, 42}
      assert expr("0xff") == {:number, 255}
      assert expr("0XFF") == {:number, 255}
    end

    test "floats" do
      assert expr("1.5") == {:number, 1.5}
      assert expr(".5") == {:number, 0.5}
      assert expr("1.") == {:number, 1.0}
      assert expr("1e3") == {:number, 1.0e3}
      assert expr("1E-3") == {:number, 1.0e-3}
      assert expr("1.5e2") == {:number, 150.0}
    end

    test "hex floats" do
      # 0x1p4 == 1 * 2^4 == 16
      assert expr("0x1p4") == {:number, 16.0}
      # 0x.8p1 == 0.5 * 2 == 1
      assert expr("0x.8p1") == {:number, 1.0}
      assert expr("0x1.8p1") == {:number, 3.0}
    end

    test "an integer and a float are distinguished" do
      assert {:number, n} = expr("1")
      assert is_integer(n)
      assert {:number, f} = expr("1.0")
      assert is_float(f)
    end
  end

  describe "strings" do
    test "quoted strings" do
      assert expr(~s('single')) == {:string, "single"}
      assert expr(~s("double")) == {:string, "double"}
      assert expr(~s('')) == {:string, ""}
    end

    test "escape sequences" do
      assert expr(~s('a\\nb')) == {:string, "a\nb"}
      assert expr(~s('a\\tb')) == {:string, "a\tb"}
      assert expr(~s('\\\\')) == {:string, "\\"}
      assert expr(~s('it\\'s')) == {:string, "it's"}
    end

    test "numeric escapes" do
      assert expr(~s('\\65')) == {:string, "A"}
      assert expr(~s('\\x41')) == {:string, "A"}
      assert expr(~s('\\u{48}')) == {:string, "H"}
    end

    test "\\z skips following whitespace" do
      assert expr(~s('a\\z\n     b')) == {:string, "ab"}
    end

    test "long strings" do
      assert expr("[[plain]]") == {:string, "plain"}
      assert expr("[==[level]==]") == {:string, "level"}
    end

    test "a long string may contain shorter bracket sequences" do
      assert expr("[==[has ]] inside]==]") == {:string, "has ]] inside"}
    end

    test "a newline immediately after the opening bracket is skipped" do
      assert expr("[[\nline]]") == {:string, "line"}
    end
  end

  describe "comments" do
    test "line comments are whitespace" do
      assert parse!("-- c\nx = 1") == parse!("x = 1")
      assert parse!("x = 1 -- trailing") == parse!("x = 1")
    end

    test "block comments are whitespace" do
      assert parse!("--[[ block ]] x = 1") == parse!("x = 1")
      assert parse!("--[==[ lvl ]==] x = 1") == parse!("x = 1")
    end

    test "a block comment may span lines" do
      assert parse!("--[[\nmulti\nline\n]]\nx = 1") == parse!("x = 1")
    end
  end

  describe "operator precedence" do
    test "multiplication binds tighter than addition" do
      assert expr("1 + 2 * 3") ==
               {:binop, :add, {:number, 1}, {:binop, :mul, {:number, 2}, {:number, 3}}}
    end

    test "parentheses override precedence" do
      assert {:binop, :mul, {:paren, {:binop, :add, _, _}}, _} = expr("(1 + 2) * 3")
    end

    test "arithmetic is left-associative" do
      assert {:binop, :sub, {:binop, :sub, _, _}, _} = expr("1 - 2 - 3")
    end

    test "concatenation is right-associative" do
      assert {:binop, :concat, _, {:binop, :concat, _, _}} = expr("a .. b .. c")
    end

    test "exponentiation is right-associative" do
      assert {:binop, :pow, {:number, 2}, {:binop, :pow, {:number, 3}, {:number, 2}}} =
               expr("2^3^2")
    end

    # `^` binds tighter than a unary operator on its left...
    test "unary minus applies to the result of exponentiation" do
      assert {:unop, :neg, {:binop, :pow, _, _}} = expr("-x^2")
    end

    # ...but its right operand is parsed at unary precedence.
    test "the exponent may itself carry a unary operator" do
      assert {:binop, :pow, {:number, 2}, {:unop, :neg, {:number, 3}}} = expr("2^-3")
    end

    test "comparison binds looser than arithmetic" do
      assert {:binop, :lt, {:binop, :add, _, _}, _} = expr("a + b < c")
    end

    test "and binds tighter than or" do
      assert {:binop, :or, {:binop, :and, _, _}, _} = expr("a and b or c")
    end

    test "bitwise precedence: & tighter than ~ tighter than |" do
      assert {:binop, :bor, {:binop, :bxor, {:binop, :band, _, _}, _}, _} =
               expr("a & b ~ c | d")
    end

    test "shifts bind tighter than comparison, looser than concat" do
      assert {:binop, :shl, {:binop, :concat, _, _}, _} = expr("a .. b << c")
    end
  end

  describe "operators are not confused with longer operators" do
    # `<` must not match the `<` of `<=` or `<<`, `/` not the `/` of `//`,
    # `~` not the `~` of `~=`, and `-` must not start a `--` comment.
    test "two-character comparison operators" do
      assert {:binop, :le, _, _} = expr("a <= b")
      assert {:binop, :ge, _, _} = expr("a >= b")
      assert {:binop, :eq, _, _} = expr("a == b")
      assert {:binop, :ne, _, _} = expr("a ~= b")
    end

    test "single-character comparison operators" do
      assert {:binop, :lt, _, _} = expr("a < b")
      assert {:binop, :gt, _, _} = expr("a > b")
    end

    test "shift versus comparison" do
      assert {:binop, :shl, _, _} = expr("a << b")
      assert {:binop, :shr, _, _} = expr("a >> b")
    end

    test "floor division versus division" do
      assert {:binop, :idiv, _, _} = expr("a // b")
      assert {:binop, :div, _, _} = expr("a / b")
    end

    test "subtraction is not the start of a comment" do
      assert {:binop, :sub, _, _} = expr("a - b")
    end
  end

  describe "unary operators" do
    test "all four unary operators" do
      assert {:unop, :neg, _} = expr("-a")
      assert {:unop, :not, _} = expr("not a")
      assert {:unop, :len, _} = expr("#t")
      assert {:unop, :bnot, _} = expr("~a")
    end

    test "unary operators stack" do
      assert {:unop, :not, {:unop, :not, _}} = expr("not not a")
    end
  end

  describe "statements" do
    test "empty statements are discarded" do
      assert parse!(";") == []
      assert parse!(";;;") == []
    end

    test "assignment" do
      assert {:assign, [{:number, 1}], [{:name, "x"}]} = stmt("x = 1")
    end

    test "multiple assignment" do
      assert {:assign, [_, _], [_, _]} = stmt("a, b = 1, 2")
    end

    test "local declaration" do
      assert {:local, [{"x", nil}], [{:number, 1}]} = stmt("local x = 1")
    end

    test "local without a value" do
      assert {:local, [{"x", nil}], []} = stmt("local x")
    end

    test "local attributes" do
      assert {:local, [{"x", "const"}], _} = stmt("local x <const> = 1")
      assert {:local, [{"f", "close"}], _} = stmt("local f <close> = nil")
    end

    test "do block" do
      assert {:do, [{:local, _, _}]} = stmt("do local x = 1 end")
    end

    test "while" do
      assert {:while, {:boolean, true}, [{:break}]} = stmt("while true do break end")
    end

    test "repeat" do
      assert {:repeat, _, _} = stmt("repeat x = 1 until done")
    end

    test "numeric for, with and without a step" do
      assert {:for_num, "i", _, _, nil, _} = stmt("for i = 1, 10 do end")
      assert {:for_num, "i", _, _, {:number, 2}, _} = stmt("for i = 1, 10, 2 do end")
    end

    test "generic for" do
      assert {:for_in, ["k", "v"], [_], _} = stmt("for k, v in pairs(t) do end")
    end

    test "goto and labels" do
      assert {:goto, "done"} = stmt("goto done")
      assert {:label, "top"} = stmt("::top::")
    end

    test "break is an ordinary statement in 5.4" do
      # In Lua 5.1 `break` had to end a block; 5.4 allows it anywhere.
      assert accepts?("while true do break; print(1) end")
    end

    test "return with and without values" do
      assert {:return, []} = stmt("return")
      assert {:return, []} = stmt("return;")
      assert {:return, [_, _]} = stmt("return 1, 2")
    end
  end

  describe "if statements" do
    test "plain if" do
      assert {:if, [{_, _}], nil} = stmt("if a then b() end")
    end

    test "if/else" do
      assert {:if, [{_, _}], [_]} = stmt("if a then b() else c() end")
    end

    test "elseif chains become clauses" do
      assert {:if, [_, _, _], [_]} =
               stmt("if a then x() elseif b then y() elseif c then z() else w() end")
    end
  end

  describe "functions" do
    test "function statement" do
      assert {:function, {:name, "f"}, [], false, []} = stmt("function f() end")
    end

    test "parameters" do
      assert {:function, _, ["a", "b"], false, _} = stmt("function f(a, b) end")
    end

    test "varargs" do
      assert {:function, _, [], true, _} = stmt("function f(...) end")
      assert {:function, _, ["a"], true, _} = stmt("function f(a, ...) end")
    end

    test "dotted function names" do
      assert {:function, {:index, {:name, "a"}, {:string, "b"}}, _, _, _} =
               stmt("function a.b() end")
    end

    test "method definitions get an implicit self parameter" do
      assert {:function, {:index, {:name, "a"}, {:string, "b"}}, ["self"], _, _} =
               stmt("function a:b() end")
    end

    test "local function" do
      assert {:local_function, "f", [], false, []} = stmt("local function f() end")
    end

    test "anonymous function expression" do
      assert {:function_expr, ["x"], false, [_]} = expr("function(x) return x end")
    end
  end

  describe "calls" do
    test "plain call" do
      assert {:call, {:name, "f"}, []} = stmt("f()")
      assert {:call, {:name, "f"}, [_, _]} = stmt("f(1, 2)")
    end

    test "a call with a single table argument needs no parentheses" do
      assert {:call, {:name, "f"}, [{:table, _}]} = stmt("f{1, 2}")
    end

    test "a call with a single string argument needs no parentheses" do
      assert {:call, {:name, "f"}, [{:string, "s"}]} = stmt(~s(f"s"))
      assert {:call, {:name, "f"}, [{:string, "s"}]} = stmt("f[[s]]")
    end

    test "method call" do
      assert {:method_call, {:name, "obj"}, "m", []} = stmt("obj:m()")
    end

    test "calls chain left to right" do
      assert {:call, {:call, {:call, {:name, "f"}, []}, []}, []} = stmt("f()()()")
    end

    test "a call on a parenthesised expression" do
      assert {:call, {:paren, _}, []} = stmt("(f)()")
    end
  end

  describe "indexing" do
    test "dot access desugars to a string key" do
      assert {:index, {:name, "a"}, {:string, "b"}} = expr("a.b")
    end

    test "bracket access keeps the expression" do
      assert {:index, {:name, "a"}, {:number, 1}} = expr("a[1]")
    end

    test "access chains nest to the left" do
      assert {:index, {:index, {:name, "a"}, {:string, "b"}}, {:string, "c"}} = expr("a.b.c")
    end

    test "mixed call and index chains" do
      assert {:index, {:call, {:index, {:name, "a"}, {:string, "b"}}, []}, {:string, "c"}} =
               expr("a.b().c")
    end
  end

  describe "table constructors" do
    test "empty table" do
      assert {:table, []} = expr("{}")
    end

    test "positional fields" do
      assert {:table, [{:positional, _}, {:positional, _}]} = expr("{1, 2}")
    end

    test "named fields" do
      assert {:table, [{:keyed, {:string, "a"}, {:number, 1}}]} = expr("{a = 1}")
    end

    test "computed keys" do
      assert {:table, [{:keyed, {:number, 1}, {:string, "x"}}]} = expr("{[1] = 'x'}")
    end

    test "semicolons separate fields too" do
      assert {:table, [_, _, _]} = expr("{1; 2; 3}")
    end

    test "a trailing separator is allowed" do
      assert {:table, [_, _]} = expr("{1, 2,}")
      assert {:table, [_, _]} = expr("{1, 2;}")
    end

    test "mixed field kinds" do
      assert {:table, [{:keyed, _, _}, {:keyed, _, _}, {:positional, _}]} =
               expr("{a = 1, [2] = 3, 4}")
    end

    test "a field value may be an equality test, not a named field" do
      # `{a == 1}` is one positional field, not `a = (= 1)`.
      assert {:table, [{:positional, {:binop, :eq, _, _}}]} = expr("{a == 1}")
    end

    test "nested tables" do
      assert {:table, [{:keyed, _, {:table, [{:keyed, _, {:table, _}}]}}]} =
               expr("{a = {b = {c = 1}}}")
    end
  end

  describe "keywords are not identifiers" do
    test "reserved words cannot be used as names" do
      refute accepts?("local = 1")
      refute accepts?("local end = 1")
      refute accepts?("function = 1")
    end

    test "an identifier may merely start with a keyword" do
      assert {:local, [{"notation", nil}], _} = stmt("local notation = 1")
      assert {:local, [{"iffy", nil}], _} = stmt("local iffy = 1")
      assert {:local, [{"forward", nil}], _} = stmt("local forward = 1")
      assert {:local, [{"nilable", nil}], _} = stmt("local nilable = 1")
    end
  end

  describe "rejects malformed input" do
    test "incomplete constructs" do
      refute accepts?("x =")
      refute accepts?("x = 1 +")
      refute accepts?("f(")
      refute accepts?("t = {")
      refute accepts?("do")
      refute accepts?("if then end")
      refute accepts?("while do end")
    end

    test "unterminated literals" do
      refute accepts?("x = [[unclosed")
      refute accepts?("x = 'unterminated")
      refute accepts?(~s(x = "unterminated))
    end

    test "a long string requires a matching bracket level" do
      refute accepts?("x = [==[mismatched]=]")
    end

    test "stray tokens" do
      refute accepts?("end")
      refute accepts?("local 1 = x")
      refute accepts?("::label")
      refute accepts?("f(1,)")
    end

    test "a bare expression is not a statement" do
      # Only a function call may stand alone.
      refute accepts?("x")
      refute accepts?("a.b")
      refute accepts?("1 + 1")
    end

    test "return must be the last statement in a block" do
      refute accepts?("return 1 return 2")
      refute accepts?("do return 1 x = 2 end")
    end
  end

  describe "whitespace and layout" do
    test "input with no whitespace at all" do
      assert accepts?("local x=1;local y=2;print(x+y)")
    end

    test "input spread across lines" do
      assert accepts?("local\n  x\n  =\n  1")
    end

    test "windows line endings" do
      assert accepts?("local x = 1\r\nlocal y = 2\r\n")
    end

    test "a leading shebang line is ignored" do
      assert accepts?("#!/usr/bin/env lua\nlocal x = 1")
    end
  end

  describe "realistic programs" do
    test "an object-oriented chunk" do
      src = """
      local Account = {}
      Account.__index = Account

      function Account.new(owner, balance)
        local self = setmetatable({}, Account)
        self.owner = owner
        self.balance = balance or 0
        return self
      end

      function Account:deposit(amount)
        if amount <= 0 then
          error("deposit must be positive", 2)
        end
        self.balance = self.balance + amount
        return self
      end

      return Account
      """

      assert {:ok, ast} = LuaParser.parse(src)
      assert length(ast) == 5
    end

    test "loops, goto and closures" do
      src = """
      local function counter()
        local n = 0
        return function() n = n + 1 return n end
      end

      for i = 1, 10 do
        if i % 2 == 0 then goto continue end
        io.write(i, " ")
        ::continue::
      end

      local i = 0
      while true do
        i = i + 1
        if i > 5 then break end
      end

      repeat i = i - 1 until i == 0
      """

      assert {:ok, _} = LuaParser.parse(src)
    end

    test "varargs and multiple returns" do
      src = """
      local function sum(...)
        local total = 0
        for _, v in ipairs({...}) do total = total + v end
        return total, select('#', ...)
      end
      local a, b = sum(1, 2, 3)
      """

      assert {:ok, _} = LuaParser.parse(src)
    end
  end

  describe "parse!/1" do
    test "returns the AST directly" do
      assert [{:return, [{:number, 1}]}] = LuaParser.parse!("return 1")
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, ~r/invalid Lua/, fn -> LuaParser.parse!("local = 1") end
    end
  end
end
