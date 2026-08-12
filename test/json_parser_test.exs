defmodule JsonParserTest do
  use ExUnit.Case
  doctest JsonParser

  describe "scalars" do
    test "integers" do
      assert {:ok, 0} = JsonParser.parse("0")
      assert {:ok, 42} = JsonParser.parse("42")
      assert {:ok, -17} = JsonParser.parse("-17")
    end

    test "floats and exponents" do
      assert {:ok, 2.5} = JsonParser.parse("2.5")
      assert {:ok, -0.5} = JsonParser.parse("-0.5")
      assert {:ok, 300.0} = JsonParser.parse("3e2")
      assert {:ok, 0.0015} = JsonParser.parse("1.5e-3")
      assert {:ok, 1.0e10} = JsonParser.parse("1E10")
    end

    test "booleans and null" do
      assert {:ok, true} = JsonParser.parse("true")
      assert {:ok, false} = JsonParser.parse("false")
      assert {:ok, nil} = JsonParser.parse("null")
    end

    test "strings" do
      assert {:ok, "hello"} = JsonParser.parse(~s("hello"))
      assert {:ok, ""} = JsonParser.parse(~s(""))
    end

    test "string escapes" do
      assert {:ok, "a\nb"} = JsonParser.parse(~S("a\nb"))
      assert {:ok, "tab\there"} = JsonParser.parse(~S("tab\there"))
      assert {:ok, ~s(quote " here)} = JsonParser.parse(~S("quote \" here"))
      assert {:ok, "back\\slash"} = JsonParser.parse(~S("back\\slash"))
      assert {:ok, "slash/here"} = JsonParser.parse(~S("slash\/here"))
    end

    test "unicode escapes" do
      assert {:ok, "A"} = JsonParser.parse(~S("A"))
      assert {:ok, "★"} = JsonParser.parse(~S("★"))
    end

    test "non-ascii content passes through" do
      assert {:ok, "héllo ★"} = JsonParser.parse(~s("héllo ★"))
    end
  end

  describe "arrays" do
    test "empty array" do
      assert {:ok, []} = JsonParser.parse("[]")
    end

    test "flat array" do
      assert {:ok, [1, 2, 3]} = JsonParser.parse("[1, 2, 3]")
    end

    test "mixed array" do
      assert {:ok, [1, "two", true, nil]} = JsonParser.parse(~s([1, "two", true, null]))
    end

    test "nested arrays" do
      assert {:ok, [[1, 2], [3, [4]]]} = JsonParser.parse("[[1,2],[3,[4]]]")
    end
  end

  describe "objects" do
    test "empty object" do
      assert {:ok, %{}} = JsonParser.parse("{}")
    end

    test "flat object" do
      assert {:ok, %{"a" => 1, "b" => 2}} = JsonParser.parse(~s({"a": 1, "b": 2}))
    end

    test "nested object and array" do
      assert {:ok, %{"a" => %{"b" => [1, 2]}, "c" => nil}} =
               JsonParser.parse(~s({"a": {"b": [1, 2]}, "c": null}))
    end

    test "duplicate keys keep the last value" do
      assert {:ok, %{"a" => 2}} = JsonParser.parse(~s({"a": 1, "a": 2}))
    end
  end

  describe "whitespace" do
    test "ignores insignificant whitespace" do
      assert {:ok, %{"a" => [1, 2]}} = JsonParser.parse(~s(  {  "a" : [ 1 , 2 ]  }  ))
    end

    test "handles newlines between tokens" do
      json = "{\n  \"a\": 1,\n  \"b\": 2\n}\n"
      assert {:ok, %{"a" => 1, "b" => 2}} = JsonParser.parse(json)
    end
  end

  describe "errors" do
    test "trailing comma in array" do
      assert {:error, _} = JsonParser.parse("[1, 2,]")
    end

    test "missing value" do
      assert {:error, _} = JsonParser.parse(~s({"a": }))
    end

    test "unclosed object" do
      assert {:error, _} = JsonParser.parse(~s({"a": 1))
    end

    test "trailing junk after a valid document" do
      assert {:error, reason} = JsonParser.parse("[1, 2] extra")
      assert reason =~ "line 1, column 8"
    end

    test "empty input" do
      assert {:error, _} = JsonParser.parse("")
    end
  end

  describe "parse!/1" do
    test "returns the value" do
      assert %{"ok" => true} = JsonParser.parse!(~s({"ok": true}))
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, ~r/invalid JSON/, fn -> JsonParser.parse!("{") end
    end
  end
end
