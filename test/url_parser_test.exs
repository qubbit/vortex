defmodule UrlParserTest do
  use ExUnit.Case

  describe "url parser" do
    test "parses a url with credentials" do
      assert {:ok, _tree} = UrlParser.parse("http://admin:password@www.google.com")
    end

    test "parses a url without credentials" do
      assert {:ok, _tree} = UrlParser.parse("https://www.google.com")
    end

    test "rejects a string that is not a url" do
      assert {:error, _reason} = UrlParser.parse("not a url")
    end
  end
end
