# <img src="artifacts/logo.png" width="32"> Vortex

A small parser combinator library for Elixir, plus a LISP parser and evaluator
built on top of it.

## Overview

Vortex has three layers:

1. **`Combinators`** — the core combinators (`str`, `char`, `any`, `seq`,
   `alt`, `opt`, `rep`, `map`, `lazy`, `ref`) and derived helpers in
   `Combinators.Builtin` (`many`, `many1`, `sep_by`, `sep_by1`, `choice`,
   `between`, `one_of`, `none_of`, plus the `<|>` alternation operator and
   lexical helpers like `integer`/`digits`). Every combinator is a function
   `State -> {nodes, new_state} | nil`.
2. **`Parser`** — runs a grammar against a string and returns `{:ok, tree}`
   when it matches the whole input, or `{:error, reason}` otherwise.
3. **`LispParser` / `Evaluator`** — a worked example: a LISP reader that turns
   source into an AST, and a Scheme-flavoured evaluator that runs it.

## Combinators

```elixir
import Combinators
import Combinators.Builtin

# a comma-separated list of integers between brackets
grammar = between(str("["), str("]"), sep_by(integer(), str(",")))

Parser.parse("[1,2,3]", grammar)
#=> {:ok, [...parse tree...]}
```

`lazy/1` lets grammars refer to themselves without looping while they are
being built:

```elixir
def parens, do: seq([str("("), opt(lazy(&parens/0)), str(")")])
```

Other primitives include `eof` (assert end of input), `followed_by` /
`not_followed_by` (positive / negative lookahead), and `count` / `rep_range`
(exact and bounded repetition).

### Error messages

When a parse fails, `Parser.parse/2` reports the furthest position it reached
and what was expected there, with a line and column:

```elixir
Parser.parse("goodbye", str("hello"))
#=> {:error, ~s(line 1, column 1: expected "hello")}
```

## LISP parser

`LispParser.parse/1` reads one or more top-level forms into a compact AST;
`parse_one/1` requires exactly one form. Numbers, strings (with escapes),
booleans (`#t`/`#f`), symbols, lists, quotes and `;` line comments are all
supported.

```elixir
LispParser.parse("(+ 1 2)")
#=> {:ok, [{:list, [{:symbol, "+"}, {:number, 1}, {:number, 2}]}]}

LispParser.parse_one("'(1 2.5 \"three\")")
#=> {:ok, {:quote, {:list, [{:number, 1}, {:number, 2.5}, {:string, "three"}]}}}
```

## LISP evaluator

`Evaluator.eval/1` parses and runs a program, returning the value of the last
form. It supports `quote`, `if`, `cond`, `define`, `lambda`, `let`, `let*`,
`and`, `or`, `begin` and `set!`, plus a standard library of numeric, list and
higher-order procedures.

```elixir
Evaluator.eval("(define (square x) (* x x)) (square 9)")
#=> {:ok, 81}

Evaluator.eval("(map (lambda (x) (* x x)) '(1 2 3 4))")
#=> {:ok, [1, 4, 9, 16]}

Evaluator.eval_file("examples/quicksort.lisp")
#=> {:ok, [1, 1, 2, 3, 3, 4, 5, 5, 5, 6, 9]}
```

Runnable sample programs (quicksort, factorial, Fibonacci, higher-order
functions and classic recursive algorithms) live in [`examples/`](examples).

## Development

```
mix test               # run the suite
mix docs               # build documentation (requires ex_doc)
mix run bench/bench.exs # rough combinator benchmarks
```

Parsing is linear in the length of the input: the `State` carries the
unconsumed suffix so position access is O(1) amortized, and `seq`/`rep` build
their result lists without quadratic appends.

## Attributions

Logo: vortex by Eliricon from the Noun Project
