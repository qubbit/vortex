defmodule Evaluator do
  @moduledoc """
  A small Scheme-flavoured evaluator for the AST produced by `LispParser`.

  It walks the parse result and computes a value, supporting the special forms
  `quote`, `if`, `cond` (with `else`), `define`, `lambda`, `let`, `let*`, `and`,
  `or`, `begin` and `set!`, plus a standard library of numeric, list and
  higher-order procedures (see `builtins/0`).

  Runtime values map onto Elixir values:

    * numbers  -> integers / floats
    * strings  -> binaries
    * booleans -> `true` / `false` (only `false` is falsy, as in Scheme)
    * lists    -> Elixir lists (`'()` is `[]`)
    * symbols  -> `{:symbol, name}`
    * closures -> `{:closure, params, body, env}`
    * builtins -> `{:builtin, name, fun}`

  The global scope is held in an `Agent` for the duration of a single run so
  that top-level `define`s are visible to (mutually) recursive functions, while
  `lambda`/`let` introduce immutable, lexically-scoped local frames.

  ## Examples

      iex> Evaluator.eval("(+ 1 2 3)")
      {:ok, 6}

      iex> Evaluator.eval("(define (sq x) (* x x)) (sq 9)")
      {:ok, 81}

      iex> Evaluator.eval("(map (lambda (x) (* x x)) '(1 2 3 4))")
      {:ok, [1, 4, 9, 16]}
  """

  @special_forms ~w(quote if cond define lambda let let* and or begin set!)

  # --- public API ----------------------------------------------------------

  @doc """
  Parse and evaluate `source`, returning `{:ok, value}` for the last top-level
  form, or `{:error, reason}` on a parse or runtime error.
  """
  @spec eval(binary) :: {:ok, any} | {:error, binary}
  def eval(source) when is_binary(source) do
    case LispParser.parse(source) do
      {:ok, forms} -> run_forms(forms)
      {:error, _} = error -> error
    end
  end

  @doc """
  Like `eval/1` but returns the value directly and raises on error.
  """
  @spec eval!(binary) :: any
  def eval!(source) when is_binary(source) do
    case eval(source) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Read a `.lisp` file from disk and evaluate its contents with `eval/1`.
  """
  @spec eval_file(binary) :: {:ok, any} | {:error, binary}
  def eval_file(path), do: path |> File.read!() |> eval()

  @doc """
  Render a runtime value the way a Scheme `display` would: strings without
  quotes, booleans as `#t`/`#f`, lists in parentheses.
  """
  @spec render(any) :: binary
  def render(value), do: do_render(value)

  # --- evaluation core -----------------------------------------------------

  defp run_forms(forms) do
    {:ok, pid} = Agent.start_link(fn -> builtins() end)
    env = %{local: [], global: pid}

    try do
      value = Enum.reduce(forms, [], fn form, _acc -> eval_ast(form, env) end)
      {:ok, value}
    rescue
      e in [ArgumentError, RuntimeError, ArithmeticError] -> {:error, Exception.message(e)}
    after
      Agent.stop(pid)
    end
  end

  defp eval_ast({:number, n}, _env), do: n
  defp eval_ast({:string, s}, _env), do: s
  defp eval_ast({:bool, b}, _env), do: b
  defp eval_ast({:symbol, name}, env), do: lookup(env, name)
  defp eval_ast({:quote, datum}, _env), do: to_datum(datum)

  defp eval_ast({:list, [{:symbol, name} | args]}, env) when name in @special_forms do
    eval_special(name, args, env)
  end

  defp eval_ast({:list, [op | args]}, env) do
    apply_fn(eval_ast(op, env), eval_args(args, env))
  end

  defp eval_ast({:list, []}, _env) do
    raise ArgumentError, "cannot evaluate the empty combination ()"
  end

  defp eval_args(args, env), do: Enum.map(args, &eval_ast(&1, env))

  defp eval_seq([], _env), do: []
  defp eval_seq(forms, env), do: Enum.reduce(forms, [], fn f, _ -> eval_ast(f, env) end)

  # --- special forms -------------------------------------------------------

  defp eval_special("quote", [datum], _env), do: to_datum(datum)

  defp eval_special("if", [test, then_form], env) do
    if truthy?(eval_ast(test, env)), do: eval_ast(then_form, env), else: false
  end

  defp eval_special("if", [test, then_form, else_form], env) do
    if truthy?(eval_ast(test, env)),
      do: eval_ast(then_form, env),
      else: eval_ast(else_form, env)
  end

  defp eval_special("cond", clauses, env), do: eval_cond(clauses, env)

  defp eval_special("define", [{:symbol, name}, value_form], env) do
    define(env, name, eval_ast(value_form, env))
    {:symbol, name}
  end

  defp eval_special("define", [{:list, [{:symbol, name} | params]} | body], env) do
    define(env, name, {:closure, param_names(params), body, env})
    {:symbol, name}
  end

  defp eval_special("lambda", [{:list, params} | body], env) do
    {:closure, param_names(params), body, env}
  end

  defp eval_special("let", [{:list, bindings} | body], env) do
    frame =
      Enum.reduce(bindings, %{}, fn {:list, [{:symbol, name}, form]}, acc ->
        Map.put(acc, name, eval_ast(form, env))
      end)

    eval_seq(body, extend(env, frame))
  end

  defp eval_special("let*", [{:list, bindings} | body], env) do
    inner_env =
      Enum.reduce(bindings, env, fn {:list, [{:symbol, name}, form]}, acc_env ->
        extend(acc_env, %{name => eval_ast(form, acc_env)})
      end)

    eval_seq(body, inner_env)
  end

  defp eval_special("and", args, env) do
    Enum.reduce_while(args, true, fn form, _ ->
      value = eval_ast(form, env)
      if truthy?(value), do: {:cont, value}, else: {:halt, false}
    end)
  end

  defp eval_special("or", args, env) do
    Enum.reduce_while(args, false, fn form, _ ->
      value = eval_ast(form, env)
      if truthy?(value), do: {:halt, value}, else: {:cont, false}
    end)
  end

  defp eval_special("begin", args, env), do: eval_seq(args, env)

  defp eval_special("set!", [{:symbol, name}, value_form], env) do
    value = eval_ast(value_form, env)
    set_var(env, name, value)
    value
  end

  defp eval_special(name, _args, _env) do
    raise ArgumentError, "ill-formed special form: #{name}"
  end

  defp eval_cond([], _env), do: false

  defp eval_cond([{:list, [{:symbol, "else"} | body]} | _rest], env), do: eval_seq(body, env)

  defp eval_cond([{:list, [test | body]} | rest], env) do
    value = eval_ast(test, env)

    cond do
      not truthy?(value) -> eval_cond(rest, env)
      body == [] -> value
      true -> eval_seq(body, env)
    end
  end

  defp param_names(params), do: Enum.map(params, fn {:symbol, name} -> name end)

  # --- application ---------------------------------------------------------

  defp apply_fn({:builtin, _name, fun}, args), do: fun.(args)

  defp apply_fn({:closure, params, body, captured_env}, args) do
    unless length(params) == length(args) do
      raise ArgumentError,
            "arity mismatch: expected #{length(params)} argument(s), got #{length(args)}"
    end

    frame = params |> Enum.zip(args) |> Map.new()
    eval_seq(body, extend(captured_env, frame))
  end

  defp apply_fn(other, _args), do: raise(ArgumentError, "not a procedure: #{do_render(other)}")

  # --- environment ---------------------------------------------------------

  defp lookup(%{local: locals, global: pid}, name) do
    case find_local(locals, name) do
      {:ok, value} ->
        value

      :error ->
        case Agent.get(pid, &Map.fetch(&1, name)) do
          {:ok, value} -> value
          :error -> raise ArgumentError, "unbound symbol: #{name}"
        end
    end
  end

  defp find_local([], _name), do: :error

  defp find_local([frame | rest], name) do
    case Map.fetch(frame, name) do
      {:ok, value} -> {:ok, value}
      :error -> find_local(rest, name)
    end
  end

  defp define(%{global: pid}, name, value), do: Agent.update(pid, &Map.put(&1, name, value))

  defp set_var(%{local: locals, global: pid}, name, value) do
    cond do
      match?({:ok, _}, find_local(locals, name)) ->
        raise ArgumentError, "set! on the local binding '#{name}' is not supported"

      Agent.get(pid, &Map.has_key?(&1, name)) ->
        Agent.update(pid, &Map.put(&1, name, value))

      true ->
        raise ArgumentError, "set!: unbound symbol #{name}"
    end
  end

  defp extend(%{local: locals} = env, frame), do: %{env | local: [frame | locals]}

  # --- quoted data ---------------------------------------------------------

  defp to_datum({:number, n}), do: n
  defp to_datum({:string, s}), do: s
  defp to_datum({:bool, b}), do: b
  defp to_datum({:symbol, name}), do: {:symbol, name}
  defp to_datum({:list, items}), do: Enum.map(items, &to_datum/1)
  defp to_datum({:quote, datum}), do: [{:symbol, "quote"}, to_datum(datum)]

  # --- truthiness & rendering ---------------------------------------------

  defp truthy?(false), do: false
  defp truthy?(_), do: true

  defp do_render(n) when is_integer(n) or is_float(n), do: to_string(n)
  defp do_render(s) when is_binary(s), do: s
  defp do_render(true), do: "#t"
  defp do_render(false), do: "#f"
  defp do_render({:symbol, name}), do: name
  defp do_render([]), do: "()"
  defp do_render(list) when is_list(list), do: "(" <> Enum.map_join(list, " ", &do_render/1) <> ")"
  defp do_render({:builtin, name, _fun}), do: "#<procedure:#{name}>"
  defp do_render({:closure, _p, _b, _e}), do: "#<procedure>"

  # --- standard library ----------------------------------------------------

  defp builtins do
    %{
      "+" => bi("+", fn args -> Enum.reduce(args, 0, &(&2 + num(&1))) end),
      "*" => bi("*", fn args -> Enum.reduce(args, 1, &(&2 * num(&1))) end),
      "-" => bi("-", &builtin_sub/1),
      "/" => bi("/", &builtin_div/1),
      "=" => bi("=", fn args -> chain(args, &==/2) end),
      "<" => bi("<", fn args -> chain(args, &</2) end),
      ">" => bi(">", fn args -> chain(args, &>/2) end),
      "<=" => bi("<=", fn args -> chain(args, &<=/2) end),
      ">=" => bi(">=", fn args -> chain(args, &>=/2) end),
      "not" => bi("not", fn [x] -> not truthy?(x) end),
      "eq?" => bi("eq?", fn [a, b] -> a == b end),
      "equal?" => bi("equal?", fn [a, b] -> a == b end),
      "zero?" => bi("zero?", fn [x] -> num(x) == 0 end),
      "even?" => bi("even?", fn [x] -> rem(num(x), 2) == 0 end),
      "odd?" => bi("odd?", fn [x] -> rem(num(x), 2) != 0 end),
      "number?" => bi("number?", fn [x] -> is_number(x) end),
      "string?" => bi("string?", fn [x] -> is_binary(x) end),
      "boolean?" => bi("boolean?", fn [x] -> is_boolean(x) end),
      "symbol?" => bi("symbol?", fn [x] -> match?({:symbol, _}, x) end),
      "null?" => bi("null?", fn [x] -> x == [] end),
      "pair?" => bi("pair?", fn [x] -> is_list(x) and x != [] end),
      "list?" => bi("list?", fn [x] -> is_list(x) end),
      "car" => bi("car", fn [[h | _]] -> h end),
      "cdr" => bi("cdr", fn [[_ | t]] -> t end),
      "cons" => bi("cons", &builtin_cons/1),
      "list" => bi("list", fn args -> args end),
      "append" => bi("append", fn args -> Enum.reduce(args, [], fn l, acc -> acc ++ as_list(l) end) end),
      "length" => bi("length", fn [l] -> length(as_list(l)) end),
      "reverse" => bi("reverse", fn [l] -> Enum.reverse(as_list(l)) end),
      "list-ref" => bi("list-ref", &builtin_list_ref/1),
      "member" => bi("member", &builtin_member/1),
      "map" => bi("map", fn [f, l] -> Enum.map(as_list(l), &apply_fn(f, [&1])) end),
      "filter" => bi("filter", fn [f, l] -> Enum.filter(as_list(l), &truthy?(apply_fn(f, [&1]))) end),
      "foldl" => bi("foldl", fn [f, acc, l] -> Enum.reduce(as_list(l), acc, &apply_fn(f, [&1, &2])) end),
      "foldr" => bi("foldr", fn [f, acc, l] -> List.foldr(as_list(l), acc, &apply_fn(f, [&1, &2])) end),
      "apply" => bi("apply", &builtin_apply/1),
      "abs" => bi("abs", fn [x] -> abs(num(x)) end),
      "min" => bi("min", fn args -> args |> Enum.map(&num/1) |> Enum.min() end),
      "max" => bi("max", fn args -> args |> Enum.map(&num/1) |> Enum.max() end),
      "modulo" => bi("modulo", fn [a, b] -> Integer.mod(num(a), num(b)) end),
      "remainder" => bi("remainder", fn [a, b] -> rem(num(a), num(b)) end),
      "quotient" => bi("quotient", fn [a, b] -> div(num(a), num(b)) end),
      "gcd" => bi("gcd", fn [a, b] -> Integer.gcd(num(a), num(b)) end),
      "expt" => bi("expt", &builtin_expt/1),
      "sqrt" => bi("sqrt", fn [x] -> :math.sqrt(num(x)) end),
      "display" => bi("display", fn [x] -> IO.write(do_render(x)) && [] end),
      "newline" => bi("newline", fn [] -> IO.write("\n") && [] end)
    }
  end

  defp bi(name, fun), do: {:builtin, name, fun}

  defp builtin_sub([]), do: raise(ArgumentError, "-: needs at least one argument")
  defp builtin_sub([x]), do: -num(x)
  defp builtin_sub([x | rest]), do: Enum.reduce(rest, num(x), fn e, acc -> acc - num(e) end)

  defp builtin_div([]), do: raise(ArgumentError, "/: needs at least one argument")
  defp builtin_div([x]), do: divide(1, num(x))
  defp builtin_div([x | rest]), do: Enum.reduce(rest, num(x), fn e, acc -> divide(acc, num(e)) end)

  defp divide(_a, 0), do: raise(ArithmeticError, message: "division by zero")

  defp divide(a, b) when is_integer(a) and is_integer(b) do
    if rem(a, b) == 0, do: div(a, b), else: a / b
  end

  defp divide(a, b), do: a / b

  defp builtin_cons([a, b]) when is_list(b), do: [a | b]
  defp builtin_cons([_a, b]), do: raise(ArgumentError, "cons: second argument must be a list, got #{do_render(b)}")

  defp builtin_list_ref([l, i]) do
    list = as_list(l)

    if i >= 0 and i < length(list),
      do: Enum.at(list, i),
      else: raise(ArgumentError, "list-ref: index #{i} out of range")
  end

  defp builtin_member([x, l]) do
    case Enum.drop_while(as_list(l), &(&1 != x)) do
      [] -> false
      tail -> tail
    end
  end

  defp builtin_apply([f | rest]) when rest != [] do
    {init, [last]} = Enum.split(rest, -1)
    apply_fn(f, init ++ as_list(last))
  end

  defp builtin_expt([base, exp]) do
    b = num(base)
    e = num(exp)

    if is_integer(b) and is_integer(e) and e >= 0,
      do: Integer.pow(b, e),
      else: :math.pow(b, e)
  end

  defp num(x) when is_number(x), do: x
  defp num(x), do: raise(ArgumentError, "expected a number, got #{do_render(x)}")

  defp as_list(l) when is_list(l), do: l
  defp as_list(x), do: raise(ArgumentError, "expected a list, got #{do_render(x)}")

  defp chain([_], _op), do: true

  defp chain([a, b | rest], op) do
    if op.(num(a), num(b)), do: chain([b | rest], op), else: false
  end

  defp chain(_, _op), do: true
end
