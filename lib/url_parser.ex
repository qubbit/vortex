# This is a very limited parser for a URL.
# Refer to https://tools.ietf.org/html/rfc3986 for detailed spec
# Grammar is translated from https://github.com/antlr/grammars-v4/blob/master/url/url.g4

defmodule UrlParser do
  import Combinators
  import Combinators.Builtin

  def string, do: rep(char("0-9A-Za-z."), 0)
  def user, do: string()
  def password, do: string()
  def login, do: seq([user(), str(":"), password(), str("@")], "login")
  def hostname, do: string()
  def host_number, do: seq([digits(), str("."), digits(), str("."), digits(), str("."), digits()])
  def host do
    seq([
      opt(str("/")),
      hostname() <|> host_number()
    ])
  end
  def scheme, do: string()


  def uri_grammar do
    seq([
      scheme(),
      str("://"),
      opt(login()),
      host()
    ])
  end

  def parse(uri) do
    Parser.parse(uri, uri_grammar())
  end
end
