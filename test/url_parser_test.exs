defmodule UrlParserTest do
  use ExUnit.Case

  describe "url parser" do
    test "parses simple url" do
      IO.inspect UrlParser.parse("http://admin:password@www.google.com")
    end
  end
end
