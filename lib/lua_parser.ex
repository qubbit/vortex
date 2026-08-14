defmodule LuaParser do
  @moduledoc """
  A parser for the **complete** Lua 5.4 language, built from the Vortex
  combinators.

  `parse/1` reads a Lua chunk and returns an AST:

      iex> LuaParser.parse("local x = 1 + 2")
      {:ok, [{:local, [{"x", nil}], [{:binop, :add, {:number, 1}, {:number, 2}}]}]}

  The grammar follows the EBNF in §9 of the Lua 5.4 reference manual, and the
  operator precedence in §3.4.8, production for production. Every construct in
  the language is covered: all statement forms, `goto`/labels, local attributes
  (`<const>`, `<close>`), varargs, method definitions and calls, table
  constructors, long strings/comments with level matching (`[==[ … ]==]`), and
  the full numeric tower (integers, floats, hex, hex floats, exponents).

  ## AST shape

  Statements are tuples tagged by keyword — `{:while, cond, body}`,
  `{:if, [{cond, body}], else_body}`, `{:local, names, exprs}`. Expressions are
  `{:number, n}`, `{:string, s}`, `{:name, n}`, `{:binop, op, l, r}`,
  `{:unop, op, e}`, `{:call, target, args}`, and so on. A chunk is a `block`,
  which is a plain list of statements.

  ## Examples

      iex> LuaParser.parse("return 1")
      {:ok, [{:return, [{:number, 1}]}]}

      iex> LuaParser.parse("x = a.b.c")
      {:ok, [{:assign, [{:index, {:index, {:name, "a"}, {:string, "b"}}, {:string, "c"}}], [{:name, "x"}]}]}

      iex> match?({:error, _}, LuaParser.parse("local = 1"))
      true
  """

  use Combinators.Grammar
  import Combinators
  import Combinators.Builtin
  import Combinators.Expr

  # --- public API ----------------------------------------------------------

  @doc """
  Parse a Lua chunk, returning `{:ok, block}` or `{:error, reason}`.
  """
  @spec parse(binary) :: {:ok, list} | {:error, binary}
  def parse(source) when is_binary(source) do
    # A leading `#!` line is skipped by Lua itself, so accept it here too.
    source = strip_shebang(source)

    case Parser.parse(source, chunk()) do
      {:ok, block} -> {:ok, block}
      {:error, _} = error -> error
    end
  end

  @doc """
  Like `parse/1` but returns the AST directly and raises on error.
  """
  @spec parse!(binary) :: list
  def parse!(source) when is_binary(source) do
    case parse(source) do
      {:ok, block} -> block
      {:error, reason} -> raise ArgumentError, "invalid Lua: #{reason}"
    end
  end

  defp strip_shebang("#" <> _ = source) do
    case String.split(source, "\n", parts: 2) do
      [_shebang, rest] -> "\n" <> rest
      [_only_line] -> ""
    end
  end

  defp strip_shebang(source), do: source

  # --- lexical layer -------------------------------------------------------
  #
  # Every token is a lexeme: it consumes trailing whitespace *and comments*, so
  # the grammar rules below never mention whitespace. `space/0` is the custom
  # space consumer threaded through `lexeme/2` and `symbol/2`.

  defp space, do: rep(alt([one_of(" \t\r\n"), str("\r\n"), comment()]), 0)

  # A comment is `--` followed by either a long bracket or the rest of the line.
  defp comment do
    seq([str("--"), alt([long_bracket(), line_comment_body()])])
  end

  defp line_comment_body do
    rep(seq([not_followed_by(newline()), any()]), 0)
  end

  defp newline, do: alt([str("\r\n"), str("\n"), str("\r")])

  defp lex(parser), do: lexeme(parser, space())
  defp sym(token), do: symbol(token, space())

  # Long brackets: `[==[ ... ]==]` — the number of `=` signs must match between
  # the opening and closing delimiter. `bind/2` carries the level from the
  # opening bracket into the parser for the closing one, which a context-free
  # grammar could not express.
  defp long_bracket do
    bind(seq([str("["), text(rep(str("="), 0)), str("[")]), fn [_, _, eqs, _] ->
      level = eqs
      closing = "]" <> level <> "]"

      # A leading newline immediately after the opening bracket is skipped.
      body = rep(seq([not_followed_by(str(closing)), any()]), 0)

      map(seq([opt(newline()), text(body), str(closing)]), fn [_, _nl, content, _] ->
        content
      end)
    end)
  end

  @keywords ~w(and break do else elseif end false for function goto if in
               local nil not or repeat return then true until while)

  @name_start "A-Za-z_"
  @name_char "A-Za-z0-9_"

  # A keyword must not be the prefix of a longer identifier: `notation` starts
  # with `not` but is a Name, not the `not` operator.
  defp kw(word) do
    lex(seq([str(word), not_followed_by(char(@name_char))]))
  end

  # An identifier that is not a reserved word.
  defp name do
    raw = text(seq([char(@name_start), rep(char(@name_char), 0)]))

    lex(
      bind(raw, fn text ->
        if text in @keywords do
          # Fail: a reserved word cannot be used as a Name.
          fn state -> Combinators.Failure.record(state, "a name") end
        else
          return(text)
        end
      end)
    )
    |> label("a name")
  end

  # --- numerals ------------------------------------------------------------
  #
  # Lua 5.4 distinguishes integers from floats, and supports hexadecimal
  # literals including hex floats (`0x1p4`). Order matters: hex must be tried
  # before decimal so the leading `0` is not consumed by the decimal branch.

  defp numeral, do: label(lex(alt([hex_numeral(), decimal_numeral()])), "a number")

  defp hex_numeral do
    digits = rep(char("0-9A-Fa-f"), 1)

    mantissa =
      alt([
        # 0x1.8, 0x.8, 0x1.
        seq([digits, str("."), rep(char("0-9A-Fa-f"), 0)]),
        seq([str("."), digits]),
        digits
      ])

    exponent = seq([one_of("pP"), opt(one_of("+-")), rep(char("0-9"), 1)])

    map(
      text(seq([str("0"), one_of("xX"), mantissa, opt(exponent)])),
      &parse_hex_numeral/1
    )
  end

  defp decimal_numeral do
    digits = rep(char("0-9"), 1)

    mantissa =
      alt([
        seq([digits, str("."), rep(char("0-9"), 0)]),
        seq([str("."), digits]),
        digits
      ])

    exponent = seq([one_of("eE"), opt(one_of("+-")), digits])

    map(text(seq([mantissa, opt(exponent)])), &parse_decimal_numeral/1)
  end

  # --- string literals -----------------------------------------------------

  defp string_literal do
    label(lex(alt([long_string(), quoted_string("\""), quoted_string("'")])), "a string")
  end

  defp long_string, do: map(long_bracket(), fn content -> {:string, content} end)

  defp quoted_string(q) do
    char_parser =
      alt([
        escape_sequence(),
        map(seq([not_followed_by(alt([str(q), newline()])), any()]), fn [_, _, c] ->
          collect_text(c)
        end)
      ])

    map(seq([str(q), rep(char_parser, 0), str(q)]), fn [_, _open, chars, _close] ->
      # `rep` yields `[:rep | pieces]`; drop the label before joining.
      {:string, chars |> drop_label() |> Enum.join()}
    end)
  end

  # Each escape form consumes a different amount of input, so they are separate
  # alternatives rather than one "backslash + any char" rule. `\z` skips all
  # following whitespace and contributes nothing to the string.
  defp escape_sequence do
    alt([
      # \z — skip whitespace
      map(seq([str("\\z"), rep(one_of(" \t\r\n"), 0)]), fn _ -> "" end),
      # \xXX — exactly two hex digits
      map(text(seq([str("\\x"), count(2, char("0-9A-Fa-f"))])), fn t ->
        <<String.to_integer(String.slice(t, 2..-1//1), 16)>>
      end),
      # \u{XXX} — arbitrary hex, encoded as UTF-8
      map(text(seq([str("\\u{"), rep(char("0-9A-Fa-f"), 1), str("}")])), fn t ->
        code = t |> String.slice(3..-2//1) |> String.to_integer(16)
        <<code::utf8>>
      end),
      # \ddd — one to three decimal digits
      map(text(seq([str("\\"), rep_range(char("0-9"), 1, 3)])), fn t ->
        <<t |> String.slice(1..-1//1) |> String.to_integer()>>
      end),
      # \<newline> — a literal newline in the string
      map(seq([str("\\"), newline()]), fn _ -> "\n" end),
      # Single-character escapes
      map(seq([str("\\"), any()]), fn [_, _slash, ch] ->
        simple_escape(collect_text(ch))
      end)
    ])
  end

  defp simple_escape("a"), do: "\a"
  defp simple_escape("b"), do: "\b"
  defp simple_escape("f"), do: "\f"
  defp simple_escape("n"), do: "\n"
  defp simple_escape("r"), do: "\r"
  defp simple_escape("t"), do: "\t"
  defp simple_escape("v"), do: "\v"
  defp simple_escape("\\"), do: "\\"
  defp simple_escape("\""), do: "\""
  defp simple_escape("'"), do: "'"
  defp simple_escape(other), do: other

  # --- numeral decoding ----------------------------------------------------

  defp parse_hex_numeral(text) do
    body = String.slice(text, 2..-1//1)

    if String.contains?(body, [".", "p", "P"]) do
      {:number, parse_hex_float(body)}
    else
      {:number, String.to_integer(body, 16)}
    end
  end

  # Hex floats: mantissa is hex, but the binary exponent after `p` is decimal,
  # and scales by powers of two rather than ten.
  defp parse_hex_float(body) do
    {mantissa_part, exponent} =
      case Regex.run(~r/^([^pP]*)[pP]([+-]?\d+)$/, body) do
        [_, m, e] -> {m, String.to_integer(e)}
        nil -> {body, 0}
      end

    {int_part, frac_part} =
      case String.split(mantissa_part, ".", parts: 2) do
        [i] -> {i, ""}
        [i, f] -> {i, f}
      end

    int_value = if int_part == "", do: 0, else: String.to_integer(int_part, 16)

    frac_value =
      if frac_part == "" do
        0.0
      else
        String.to_integer(frac_part, 16) / :math.pow(16, String.length(frac_part))
      end

    (int_value + frac_value) * :math.pow(2, exponent)
  end

  defp parse_decimal_numeral(text) do
    if String.contains?(text, [".", "e", "E"]) do
      {:number, to_float(text)}
    else
      {:number, String.to_integer(text)}
    end
  end

  # Lua accepts forms Float.parse/1 rejects (`1.`, `.5`, `1e3`), so normalise
  # the mantissa before handing it over.
  defp to_float(text) do
    {mantissa, exponent} =
      case Regex.run(~r/^([^eE]*)[eE]([+-]?\d+)$/, text) do
        [_, m, e] -> {m, e}
        nil -> {text, nil}
      end

    mantissa =
      mantissa
      |> then(&if String.starts_with?(&1, "."), do: "0" <> &1, else: &1)
      |> then(&if String.ends_with?(&1, "."), do: &1 <> "0", else: &1)
      |> then(&if String.contains?(&1, "."), do: &1, else: &1 <> ".0")

    full = if exponent, do: mantissa <> "e" <> exponent, else: mantissa
    {value, ""} = Float.parse(full)
    value
  end

  # --- grammar: chunk and blocks -------------------------------------------
  #
  # Rules follow §9 of the manual production for production. `defrule` memoises
  # each rule and lets them reference each other by name without `lazy/1`.

  defrule :chunk do
    map(seq([whitespaced(return(nil), space()), block(), eof()]), fn [_, _ws, stmts, _eof] ->
      stmts
    end)
  end

  # block ::= {stat} [retstat]
  defrule :block do
    map(seq([rep(stat(), 0), opt(retstat())]), fn [_, stmts, ret] ->
      statements = stmts |> drop_label() |> Enum.reject(&(&1 == :empty))

      case single_or_nil(ret) do
        nil -> statements
        r -> statements ++ [r]
      end
    end)
  end

  # retstat ::= return [explist] [';']
  defrule :retstat do
    map(seq([kw("return"), opt(explist()), opt(sym(";"))]), fn [_, _kw, exprs, _semi] ->
      {:return, if(absent?(exprs), do: [], else: exprs)}
    end)
  end

  defrule :stat do
    alt([
      # ';' — an empty statement
      map(sym(";"), fn _ -> :empty end),
      label_stat(),
      map(kw("break"), fn _ -> {:break} end),
      map(seq([kw("goto"), name()]), fn [_, _kw, n] -> {:goto, n} end),
      do_stat(),
      while_stat(),
      repeat_stat(),
      if_stat(),
      for_numeric(),
      for_generic(),
      local_function_stat(),
      local_stat(),
      function_stat(),
      # Assignment must be tried before a bare call: `f(x)` is a call, but
      # `f(x).y = 1` is an assignment whose first var starts the same way.
      assign_stat(),
      call_stat()
    ])
  end

  # label ::= '::' Name '::'
  defrule :label_stat do
    map(seq([sym("::"), name(), sym("::")]), fn [_, _o, n, _c] -> {:label, n} end)
  end

  defrule :do_stat do
    map(seq([kw("do"), block(), kw("end")]), fn [_, _d, body, _e] -> {:do, body} end)
  end

  defrule :while_stat do
    map(seq([kw("while"), exp(), kw("do"), block(), kw("end")]), fn [_, _w, cond, _d, body, _e] ->
      {:while, cond, body}
    end)
  end

  defrule :repeat_stat do
    map(seq([kw("repeat"), block(), kw("until"), exp()]), fn [_, _r, body, _u, cond] ->
      {:repeat, body, cond}
    end)
  end

  # if exp then block {elseif exp then block} [else block] end
  defrule :if_stat do
    elseif_clause =
      map(seq([kw("elseif"), exp(), kw("then"), block()]), fn [_, _e, cond, _t, body] ->
        {cond, body}
      end)

    else_clause = map(seq([kw("else"), block()]), fn [_, _e, body] -> body end)

    map(
      seq([
        kw("if"),
        exp(),
        kw("then"),
        block(),
        rep(elseif_clause, 0),
        opt(else_clause),
        kw("end")
      ]),
      fn [_, _if, cond, _then, body, elseifs, else_body, _end] ->
        clauses = [{cond, body} | drop_label(elseifs)]
        {:if, clauses, single_or_nil(else_body)}
      end
    )
  end

  # for Name '=' exp ',' exp [',' exp] do block end
  defrule :for_numeric do
    map(
      seq([
        kw("for"),
        name(),
        sym("="),
        exp(),
        sym(","),
        exp(),
        opt(seq([sym(","), exp()])),
        kw("do"),
        block(),
        kw("end")
      ]),
      fn [_, _for, var, _eq, from, _c1, to, step, _do, body, _end] ->
        {:for_num, var, from, to, extract_step(step), body}
      end
    )
  end

  # for namelist in explist do block end
  defrule :for_generic do
    map(
      seq([kw("for"), namelist(), kw("in"), explist(), kw("do"), block(), kw("end")]),
      fn [_, _for, names, _in, exprs, _do, body, _end] ->
        {:for_in, names, exprs, body}
      end
    )
  end

  # function funcname funcbody
  defrule :function_stat do
    map(seq([kw("function"), funcname(), funcbody()]), fn [_, _f, {target, is_method}, body] ->
      {params, varargs, block} = body
      params = if is_method, do: ["self" | params], else: params
      {:function, target, params, varargs, block}
    end)
  end

  # local function Name funcbody
  defrule :local_function_stat do
    map(seq([kw("local"), kw("function"), name(), funcbody()]), fn [_, _l, _f, n, body] ->
      {params, varargs, block} = body
      {:local_function, n, params, varargs, block}
    end)
  end

  # local attnamelist ['=' explist]
  defrule :local_stat do
    map(
      seq([kw("local"), attnamelist(), opt(seq([sym("="), explist()]))]),
      fn [_, _l, names, exprs] ->
        {:local, names, extract_explist(exprs)}
      end
    )
  end

  # attnamelist ::= Name attrib {',' Name attrib}
  # attrib      ::= ['<' Name '>']
  defrule :attnamelist do
    attrib = opt(map(seq([sym("<"), name(), sym(">")]), fn [_, _o, a, _c] -> a end))

    entry =
      map(seq([name(), attrib]), fn [_, n, attr] ->
        {n, single_or_nil(attr)}
      end)

    map(seq([entry, rep(seq([sym(","), entry]), 0)]), fn [_, first, rest] ->
      [first | rest |> drop_label() |> Enum.map(fn [_, _comma, e] -> e end)]
    end)
  end

  # varlist '=' explist
  defrule :assign_stat do
    map(seq([varlist(), sym("="), explist()]), fn [_, targets, _eq, values] ->
      {:assign, values, targets}
    end)
  end

  defrule :call_stat do
    bind(prefixexp(), fn expr ->
      # Only a call is a valid statement; a bare `x` or `a.b` is not.
      case expr do
        {:call, _, _} -> return(expr)
        {:method_call, _, _, _} -> return(expr)
        _ -> fn state -> Combinators.Failure.record(state, "a function call") end
      end
    end)
  end

  # funcname ::= Name {'.' Name} [':' Name]
  defrule :funcname do
    map(
      seq([
        name(),
        rep(seq([sym("."), name()]), 0),
        opt(seq([sym(":"), name()]))
      ]),
      fn [_, first, fields, method] ->
        base =
          fields
          |> drop_label()
          |> Enum.reduce({:name, first}, fn [_, _dot, f], acc ->
            {:index, acc, {:string, f}}
          end)

        if absent?(method) do
          {base, false}
        else
          m = method |> drop_label() |> List.last()
          {{:index, base, {:string, m}}, true}
        end
      end
    )
  end

  # funcbody ::= '(' [parlist] ')' block end
  defrule :funcbody do
    map(
      seq([sym("("), opt(parlist()), sym(")"), block(), kw("end")]),
      fn [_, _o, params, _c, body, _end] ->
        {names, varargs} = if absent?(params), do: {[], false}, else: params

        {names, varargs, body}
      end
    )
  end

  # parlist ::= namelist [',' '...'] | '...'
  defrule :parlist do
    alt([
      map(seq([namelist(), opt(seq([sym(","), sym("...")]))]), fn [_, names, va] ->
        {names, not absent?(va)}
      end),
      map(sym("..."), fn _ -> {[], true} end)
    ])
  end

  defrule :namelist do
    map(seq([name(), rep(seq([sym(","), name()]), 0)]), fn [_, first, rest] ->
      [first | rest |> drop_label() |> Enum.map(fn [_, _comma, n] -> n end)]
    end)
  end

  defrule :explist do
    map(seq([exp(), rep(seq([sym(","), exp()]), 0)]), fn [_, first, rest] ->
      [first | rest |> drop_label() |> Enum.map(fn [_, _comma, e] -> e end)]
    end)
  end

  defrule :varlist do
    map(seq([var(), rep(seq([sym(","), var()]), 0)]), fn [_, first, rest] ->
      [first | rest |> drop_label() |> Enum.map(fn [_, _comma, v] -> v end)]
    end)
  end

  # var ::= Name | prefixexp '[' exp ']' | prefixexp '.' Name
  #
  # Written as a suffix loop rather than left recursion so it cannot match a
  # bare function call (which is not a valid assignment target).
  defrule :var do
    bind(prefixexp(), fn expr ->
      case expr do
        {:index, _, _} -> return(expr)
        {:name, _} -> return(expr)
        _ -> fn state -> Combinators.Failure.record(state, "a variable") end
      end
    end)
  end

  # --- grammar: expressions ------------------------------------------------

  # prefixexp ::= var | functioncall | '(' exp ')'
  #
  # The manual states this left-recursively (`var ::= prefixexp '[' exp ']'`,
  # `functioncall ::= prefixexp args`). It is written here as a primary
  # followed by a loop of suffixes, which is the standard non-left-recursive
  # formulation and folds left, giving the same associativity.
  defrule :prefixexp do
    primary =
      alt([
        map(name(), fn n -> {:name, n} end),
        map(seq([sym("("), exp(), sym(")")]), fn [_, _o, e, _c] -> {:paren, e} end)
      ])

    bind(primary, fn base -> suffix_loop(base) end)
  end

  # Repeatedly apply `.name`, `[exp]`, `:name args`, or `args` to the base.
  defp suffix_loop(base) do
    suffix =
      alt([
        map(seq([sym("."), name()]), fn [_, _dot, n] -> {:field, n} end),
        map(seq([sym("["), exp(), sym("]")]), fn [_, _o, e, _c] -> {:key, e} end),
        map(seq([sym(":"), name(), args()]), fn [_, _c, n, a] -> {:method, n, a} end),
        map(args(), fn a -> {:call, a} end)
      ])

    bind(rep(suffix, 0), fn suffixes ->
      return(Enum.reduce(drop_label(suffixes), base, &apply_suffix/2))
    end)
  end

  defp apply_suffix({:field, n}, acc), do: {:index, acc, {:string, n}}
  defp apply_suffix({:key, e}, acc), do: {:index, acc, e}
  defp apply_suffix({:method, n, a}, acc), do: {:method_call, acc, n, a}
  defp apply_suffix({:call, a}, acc), do: {:call, acc, a}

  # args ::= '(' [explist] ')' | tableconstructor | LiteralString
  defrule :args do
    alt([
      map(seq([sym("("), opt(explist()), sym(")")]), fn [_, _o, exprs, _c] ->
        if absent?(exprs), do: [], else: exprs
      end),
      map(tableconstructor(), fn t -> [t] end),
      map(string_literal(), fn s -> [s] end)
    ])
  end

  # tableconstructor ::= '{' [fieldlist] '}'
  defrule :tableconstructor do
    fieldsep = alt([sym(","), sym(";")])

    field =
      alt([
        map(seq([sym("["), exp(), sym("]"), sym("="), exp()]), fn [_, _o, k, _c, _eq, v] ->
          {:keyed, k, v}
        end),
        # `Name =` must not swallow a bare expression that merely starts with a
        # name, so require the `=` (and not `==`) before committing.
        map(
          seq([name(), sym("="), not_followed_by(str("=")), exp()]),
          fn [_, n, _eq, _nf, v] -> {:keyed, {:string, n}, v} end
        ),
        map(exp(), fn e -> {:positional, e} end)
      ])

    fieldlist =
      map(
        seq([field, rep(seq([fieldsep, field]), 0), opt(fieldsep)]),
        fn [_, first, rest, _trailing] ->
          [first | rest |> drop_label() |> Enum.map(fn [_, _sep, f] -> f end)]
        end
      )

    map(seq([sym("{"), opt(fieldlist), sym("}")]), fn [_, _o, fields, _c] ->
      {:table, if(absent?(fields), do: [], else: fields)}
    end)
  end

  # functiondef ::= function funcbody
  defrule :functiondef do
    map(seq([kw("function"), funcbody()]), fn [_, _f, {params, varargs, body}] ->
      {:function_expr, params, varargs, body}
    end)
  end

  # A simple (non-operator) expression — the `term` fed to the precedence table.
  defrule :simple_exp do
    alt([
      map(kw("nil"), fn _ -> {nil} end),
      map(kw("true"), fn _ -> {:boolean, true} end),
      map(kw("false"), fn _ -> {:boolean, false} end),
      map(sym("..."), fn _ -> {:varargs} end),
      numeral(),
      string_literal(),
      functiondef(),
      tableconstructor(),
      prefixexp()
    ])
  end

  # `^` has asymmetric precedence, which a single precedence-table level cannot
  # express: it binds tighter than a unary operator on its **left** (so `-x^2`
  # is `-(x^2)`), but its **right** operand is parsed at unary precedence (so
  # `2^-3` is valid and means `2^(-3)`). It is also right-associative.
  #
  # Written directly as `simple_exp ['^' unary_exp]` to get all three
  # properties at once.
  defrule :power do
    alt([
      map(seq([simple_exp(), op("^"), unary_exp()]), fn [_, base, _caret, exponent] ->
        binop(:pow, base, exponent)
      end),
      simple_exp()
    ])
  end

  # The right operand of `^`: any chain of unary operators applied to a power.
  # Recursing into `power/0` is what makes `^` right-associative.
  defrule :unary_exp do
    unary_op =
      alt([
        map(kw("not"), fn _ -> :not end),
        map(op("#"), fn _ -> :len end),
        map(op("-"), fn _ -> :neg end),
        map(op("~"), fn _ -> :bnot end)
      ])

    alt([
      map(seq([unary_op, unary_exp()]), fn [_, o, e] -> unop(o, e) end),
      power()
    ])
  end

  # exp ::= ... | exp binop exp | unop exp
  #
  # Built from the precedence table in §3.4.8, ordered tightest-binding first
  # (the reverse of the manual's presentation).
  defrule :exp do
    expression(power(), [
      [
        prefix(kw("not"), &unop(:not, &1)),
        prefix(op("#"), &unop(:len, &1)),
        prefix(op("-"), &unop(:neg, &1)),
        prefix(op("~"), &unop(:bnot, &1))
      ],
      [
        infixl(op("*"), &binop(:mul, &1, &2)),
        infixl(op("//"), &binop(:idiv, &1, &2)),
        infixl(op("/"), &binop(:div, &1, &2)),
        infixl(op("%"), &binop(:mod, &1, &2))
      ],
      [
        infixl(op("+"), &binop(:add, &1, &2)),
        infixl(op("-"), &binop(:sub, &1, &2))
      ],
      # `..` is right-associative.
      [infixr(op(".."), &binop(:concat, &1, &2))],
      [
        infixl(op("<<"), &binop(:shl, &1, &2)),
        infixl(op(">>"), &binop(:shr, &1, &2))
      ],
      [infixl(op("&"), &binop(:band, &1, &2))],
      [infixl(op("~"), &binop(:bxor, &1, &2))],
      [infixl(op("|"), &binop(:bor, &1, &2))],
      [
        infixl(op("=="), &binop(:eq, &1, &2)),
        infixl(op("~="), &binop(:ne, &1, &2)),
        infixl(op("<="), &binop(:le, &1, &2)),
        infixl(op(">="), &binop(:ge, &1, &2)),
        infixl(op("<"), &binop(:lt, &1, &2)),
        infixl(op(">"), &binop(:gt, &1, &2))
      ],
      [infixl(kw("and"), &binop(:and, &1, &2))],
      [infixl(kw("or"), &binop(:or, &1, &2))]
    ])
  end

  # An operator token that must not be the prefix of a longer operator:
  # `<` must not match the `<` of `<=` or `<<`, and `-` must not start `--`
  # (a comment). `Expr`'s default string handling would match greedily.
  @operator_conflicts %{
    "<" => ["=", "<"],
    ">" => ["=", ">"],
    "/" => ["/"],
    "~" => ["="],
    "=" => ["="],
    "-" => ["-"],
    "." => ["."],
    "|" => [],
    "&" => []
  }

  defp op(token) do
    case Map.get(@operator_conflicts, token) do
      nil -> sym(token)
      [] -> sym(token)
      followers -> lex(seq([str(token), not_followed_by(one_of(Enum.join(followers)))]))
    end
  end

  defp binop(op, a, b), do: {:binop, op, a, b}
  defp unop(op, e), do: {:unop, op, e}

  # --- node helpers --------------------------------------------------------

  # `rep/2` yields `[:rep | items]`. Strip that label to get the plain items.
  defp drop_label([:rep | items]), do: items
  defp drop_label([:seq | items]), do: items
  defp drop_label(other), do: other

  # `opt/1` is different: on success it passes the inner value through
  # *unchanged*, and only on absence does it yield the marker `[:opt, []]`.
  # So absence must be detected by that exact shape, not by "starts with an
  # atom" — an AST node like `{:return, …}` would be mangled by the latter.
  defp absent?([:opt, []]), do: true
  defp absent?(_), do: false

  defp single_or_nil(node) do
    if absent?(node), do: nil, else: node
  end

  # The `seq` inside an `opt` keeps its own node shape, so take the last
  # element rather than pattern-matching a fixed arity.
  defp extract_step(node) do
    if absent?(node), do: nil, else: node |> drop_label() |> List.last()
  end

  defp extract_explist(node) do
    if absent?(node), do: [], else: node |> drop_label() |> List.last()
  end
end
