# Vortex LISP examples

Small LISP / Scheme programs that run on the `LispParser` + `Evaluator` built
with the Vortex combinators. Run one from the project root with:

```
mix lisp examples/quicksort.lisp   # => (1 1 2 3 3 4 5 5 5 6 9)
mix lisp                           # start an interactive REPL
```

or from IEx:

```elixir
iex -S mix
iex> Evaluator.eval_file("examples/quicksort.lisp")
{:ok, [1, 1, 2, 3, 3, 4, 5, 5, 5, 6, 9]}
```

| File | Shows off | Result |
| --- | --- | --- |
| `quicksort.lisp` | recursion, `let`, closures over `pivot`, `filter`/`append` | `(1 1 2 3 3 4 5 5 5 6 9)` |
| `factorial.lisp` | recursive and iterative (accumulator) styles | `(3628800 3628800)` |
| `fibonacci.lisp` | `cond`, linear vs. tree recursion, `map` over a range | `(55 (0 1 1 2 3 5 8 13 21 34))` |
| `higher_order.lisp` | `map` / `filter` / `foldl`, small library functions | `((1 4 ... 100) (2 4 6 8 10) 55 5.5)` |
| `classics.lisp` | GCD, Ackermann, ranges, mutual recursion | `(12 9 45 30 #t)` |
| `quasiquote.lisp` | quasiquote/unquote/splicing, `when` | `((greeting hello world) (1 2 3 4 5) (the number 7 doubled is 14))` |

Each file ends with a single expression whose value is what `eval_file/1`
returns.
