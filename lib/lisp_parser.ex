defmodule LispParser do
  @moduledoc """
  A small LISP / S-expression parser built entirely from the `Vortex`
  combinators in `Combinators` and `Combinators.Builtin`.

  It recognises the following grammar. Whitespace — any run of spaces, tabs,
  newlines, carriage returns, and `;` line comments — is allowed between forms
  and is discarded:

      program    = ws* (expr ws*)*
      expr       = list | quote | atom
      list       = "(" (ws* expr)* ws* ")"
      quote      = "'" ws* expr
      atom       = number | string | boolean | symbol
      number     = ("+" | "-")? digits ("." digits)?
      string     = '"' ( '\\' any | not('"' | '\\') )* '"'
      boolean    = "#t" | "#f"
      symbol     = symbol_char+

  `parse/1` returns `{:ok, forms}` where `forms` is a list of the top-level
  expressions, each transformed into a compact Elixir AST:

    * numbers  -> `{:number, integer_or_float}`
    * strings  -> `{:string, unescaped_binary}`
    * booleans -> `{:bool, true | false}`
    * symbols  -> `{:symbol, binary}`
    * lists    -> `{:list, [ast, ...]}`
    * quotes   -> `{:quote, ast}`

  ## Examples

      iex> LispParser.parse("(+ 1 2)")
      {:ok, [{:list, [{:symbol, "+"}, {:number, 1}, {:number, 2}]}]}

      iex> LispParser.parse_one("'(1 2.5 \\"three\\")")
      {:ok,
       {:quote,
        {:list, [{:number, 1}, {:number, 2.5}, {:string, "three"}]}}}

      iex> match?({:error, _}, LispParser.parse("("))
      true
  """

  import Combinators
  import Combinators.Builtin, only: [many: 1, one_of: 1, none_of: 1]

  @symbol_chars "abcdefghijklmnopqrstuvwxyz" <>
                  "ABCDEFGHIJKLMNOPQRSTUVWXYZ" <>
                  "0123456789" <> "+-*/!?<>=_.:$%&^~@"

  @expr_labels [:lisp_list, :lisp_quote, :lisp_number, :lisp_string, :lisp_bool, :lisp_symbol]

  # --- public API ----------------------------------------------------------

  @doc """
  Parse `source` into a list of top-level LISP forms.

  Returns `{:ok, forms}` on success or `{:error, reason}` when the input does
  not parse as valid LISP.
  """
  @spec parse(binary) :: {:ok, [tuple]} | {:error, binary}
  def parse(source) when is_binary(source) do
    case Parser.parse(source, program()) do
      {:ok, tree} -> {:ok, program_to_ast(tree)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Parse `source`, requiring it to contain exactly one top-level form, and return
  that single form's AST.
  """
  @spec parse_one(binary) :: {:ok, tuple} | {:error, binary}
  def parse_one(source) when is_binary(source) do
    case parse(source) do
      {:ok, [form]} -> {:ok, form}
      {:ok, []} -> {:error, "expected one form, found none"}
      {:ok, forms} -> {:error, "expected one form, found #{length(forms)}"}
      error -> error
    end
  end

  @doc """
  Like `parse/1` but returns the forms directly and raises `ArgumentError` on a
  parse error.
  """
  @spec parse!(binary) :: [tuple]
  def parse!(source) when is_binary(source) do
    case parse(source) do
      {:ok, forms} -> forms
      {:error, reason} -> raise ArgumentError, "invalid LISP: #{reason}"
    end
  end

  # --- grammar -------------------------------------------------------------

  @doc false
  def program, do: seq([many(seq([ws(), lazy(&expr/0)])), ws()], :program)

  @doc false
  def expr, do: alt([list_expr(), quote_expr(), atom()])

  @doc false
  def atom, do: alt([number(), string_lit(), boolean(), symbol()])

  @doc false
  def list_expr do
    seq([str("("), many(seq([ws(), lazy(&expr/0)])), ws(), str(")")], :lisp_list)
  end

  @doc false
  def quote_expr, do: seq([str("'"), ws(), lazy(&expr/0)], :lisp_quote)

  @doc false
  def number, do: alt([float_lit(), integer_lit()])

  @doc false
  def integer_lit, do: seq([opt(one_of("+-")), digits()], :lisp_number)

  @doc false
  def float_lit, do: seq([opt(one_of("+-")), digits(), str("."), digits()], :lisp_number)

  @doc false
  def boolean, do: alt([str("#t", :lisp_bool), str("#f", :lisp_bool)])

  @doc false
  def string_lit do
    seq([str("\""), many(alt([escaped_char(), normal_char()])), str("\"")], :lisp_string)
  end

  @doc false
  def symbol, do: rep(one_of(@symbol_chars), 1, :lisp_symbol)

  @doc false
  def digits, do: rep(char("0-9", :digit), 1, :digits)

  @doc false
  def escaped_char, do: seq([str("\\"), any()])

  @doc false
  def normal_char, do: none_of("\"\\")

  @doc false
  def ws, do: rep(alt([one_of(" \t\n\r"), comment()]), 0, :ws)

  @doc false
  def comment, do: seq([str(";"), rep(none_of("\n"), 0), opt(str("\n"))])

  # --- parse tree -> AST ---------------------------------------------------

  defp program_to_ast([:program | children]) do
    children |> Enum.flat_map(&expr_nodes/1) |> Enum.map(&to_ast/1)
  end

  # Collect the direct expression nodes reachable from a parse-tree node without
  # descending past an expression boundary (so nested lists stay intact).
  defp expr_nodes([label | _] = node) when label in @expr_labels, do: [node]
  defp expr_nodes([_label | children]), do: Enum.flat_map(children, &expr_nodes/1)
  defp expr_nodes(_), do: []

  defp to_ast([:lisp_list | children]) do
    {:list, children |> Enum.flat_map(&expr_nodes/1) |> Enum.map(&to_ast/1)}
  end

  defp to_ast([:lisp_quote | children]) do
    [inner] = children |> Enum.flat_map(&expr_nodes/1)
    {:quote, to_ast(inner)}
  end

  defp to_ast([:lisp_number | _] = node), do: {:number, parse_number(collect_text(node))}

  defp to_ast([:lisp_string | _] = node) do
    raw = collect_text(node)
    inner = String.slice(raw, 1, String.length(raw) - 2)
    {:string, unescape(inner)}
  end

  defp to_ast([:lisp_bool | _] = node), do: {:bool, collect_text(node) == "#t"}

  defp to_ast([:lisp_symbol | _] = node), do: {:symbol, collect_text(node)}

  # `collect_text/1` (imported from Combinators) concatenates every string leaf
  # under a node, giving the exact substring the node consumed regardless of how
  # the combinators nested it.

  defp parse_number(text) do
    text = String.replace_prefix(text, "+", "")

    if String.contains?(text, ".") do
      String.to_float(text)
    else
      String.to_integer(text)
    end
  end

  defp unescape(<<>>), do: ""

  defp unescape(<<"\\", c, rest::binary>>) do
    decoded =
      case <<c>> do
        "n" -> "\n"
        "t" -> "\t"
        "r" -> "\r"
        "\"" -> "\""
        "\\" -> "\\"
        other -> other
      end

    decoded <> unescape(rest)
  end

  defp unescape(<<c, rest::binary>>), do: <<c>> <> unescape(rest)
end
