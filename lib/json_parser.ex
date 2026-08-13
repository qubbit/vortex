defmodule JsonParser do
  @moduledoc """
  A JSON parser built from the Vortex combinators.

  `parse/1` reads a complete JSON document and returns Elixir data:

    * objects -> maps with binary keys
    * arrays  -> lists
    * strings -> binaries (with `\\n`, `\\t`, `\\uXXXX`, ... unescaped)
    * numbers -> integers, or floats when a fraction or exponent is present
    * `true` / `false` -> booleans, `null` -> `nil`

  The grammar follows the object/array/value structure of the JSON spec and
  requires the whole input to be consumed (trailing junk is an error).

  ## Examples

      iex> JsonParser.parse(~s({"a": 1, "b": [true, null]}))
      {:ok, %{"a" => 1, "b" => [true, nil]}}

      iex> JsonParser.parse("[1, 2.5, -3e2]")
      {:ok, [1, 2.5, -300.0]}

      iex> match?({:error, _}, JsonParser.parse("[1,]"))
      true
  """

  import Combinators

  import Combinators.Builtin,
    only: [one_of: 1, none_of: 1, many: 1, sep_by: 2, lexeme: 1, symbol: 1, whitespaced: 1]

  @doc """
  Parse a JSON document, returning `{:ok, value}` or `{:error, reason}`.
  """
  @spec parse(binary) :: {:ok, term} | {:error, binary}
  def parse(source) when is_binary(source) do
    grammar = whitespaced(seq([lazy(&value/0), eof()], :json))

    case Parser.parse(source, grammar) do
      {:ok, tree} -> {:ok, to_value(find_value(tree))}
      {:error, _} = error -> error
    end
  end

  @doc """
  Like `parse/1` but returns the value directly and raises on error.
  """
  @spec parse!(binary) :: term
  def parse!(source) when is_binary(source) do
    case parse(source) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid JSON: #{reason}"
    end
  end

  # --- grammar -------------------------------------------------------------

  @value_labels [
    :json_object,
    :json_array,
    :json_string,
    :json_number,
    :json_true,
    :json_false,
    :json_null
  ]

  defp value do
    alt([
      object(),
      array(),
      string_lit(),
      number(),
      keyword("true", :json_true),
      keyword("false", :json_false),
      keyword("null", :json_null)
    ])
  end

  defp object do
    seq(
      [symbol("{"), sep_by(member(), symbol(",")), symbol("}")],
      :json_object
    )
  end

  defp member, do: seq([string_lit(), symbol(":"), lazy(&value/0)], :json_member)

  defp array do
    seq(
      [symbol("["), sep_by(lazy(&value/0), symbol(",")), symbol("]")],
      :json_array
    )
  end

  defp string_lit do
    lexeme(seq([str("\""), many(alt([escape(), normal_char()])), str("\"")], :json_string))
  end

  defp escape, do: seq([str("\\"), any()])

  defp normal_char, do: none_of("\"\\")

  defp number do
    lexeme(
      seq(
        [opt(str("-")), int_part(), opt(frac_part()), opt(exp_part())],
        :json_number
      )
    )
  end

  defp int_part, do: alt([str("0"), seq([one_of("123456789"), digits0()])])

  defp frac_part, do: seq([str("."), digits1()])

  defp exp_part, do: seq([one_of("eE"), opt(one_of("+-")), digits1()])

  defp digits0, do: rep(char("0-9"), 0)

  defp digits1, do: rep(char("0-9"), 1)

  defp keyword(word, label), do: lexeme(str(word, label))

  # --- parse tree -> Elixir value -----------------------------------------

  # Pull the single value node out of a container node's children.
  defp find_value(node), do: node |> value_nodes() |> hd()

  defp value_nodes([label | _] = node) when label in @value_labels, do: [node]
  defp value_nodes([_label | children]), do: Enum.flat_map(children, &value_nodes/1)
  defp value_nodes(_), do: []

  defp to_value([:json_object | children]) do
    children
    |> member_nodes()
    |> Map.new(fn member ->
      [key_node, value_node] = value_nodes(member)
      {to_value(key_node), to_value(value_node)}
    end)
  end

  defp to_value([:json_array | children]) do
    children |> Enum.flat_map(&value_nodes/1) |> Enum.map(&to_value/1)
  end

  defp to_value([:json_string | _] = node) do
    raw = collect_text(node)
    raw |> String.slice(1, String.length(raw) - 2) |> unescape()
  end

  defp to_value([:json_number | _] = node), do: parse_number(collect_text(node))

  defp to_value([:json_true | _]), do: true
  defp to_value([:json_false | _]), do: false
  defp to_value([:json_null | _]), do: nil

  # Members sit nested inside the `sep_by` structure, so collect them
  # recursively — but stop at each member so a member's own (possibly nested)
  # object doesn't leak its members up here.
  defp member_nodes(children), do: Enum.flat_map(children, &collect_members/1)

  defp collect_members([:json_member | _] = node), do: [node]
  defp collect_members([_label | children]), do: Enum.flat_map(children, &collect_members/1)
  defp collect_members(_other), do: []

  defp parse_number(text) do
    if String.contains?(text, ".") or String.contains?(text, "e") or String.contains?(text, "E") do
      to_float(text)
    else
      String.to_integer(text)
    end
  end

  # JSON allows `1e2` (no decimal point); Elixir's Float.parse needs digits on
  # both sides, so normalise the mantissa before parsing.
  defp to_float(text) do
    {value, ""} = Float.parse(normalise_float(text))
    value
  end

  defp normalise_float(text) do
    case Regex.run(~r/^(-?\d+)(\.\d+)?([eE][+-]?\d+)?$/, text) do
      [_, int, "", exp] -> int <> ".0" <> exp
      _ -> text
    end
  end

  defp unescape(<<>>), do: ""

  defp unescape(<<"\\u", a, b, c, d, rest::binary>>) do
    code = String.to_integer(<<a, b, c, d>>, 16)
    <<code::utf8>> <> unescape(rest)
  end

  defp unescape(<<"\\", ch, rest::binary>>) do
    decoded =
      case <<ch>> do
        "n" -> "\n"
        "t" -> "\t"
        "r" -> "\r"
        "b" -> "\b"
        "f" -> "\f"
        "/" -> "/"
        "\"" -> "\""
        "\\" -> "\\"
        other -> other
      end

    decoded <> unescape(rest)
  end

  defp unescape(<<ch::utf8, rest::binary>>), do: <<ch::utf8>> <> unescape(rest)
end
