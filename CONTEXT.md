# Vortex — project context & development notes

A running "pick this up next time" dump of what Vortex is, how it's built, and
where everything lives. Line-number links point at `master`.

Vortex is a **parser combinator library for Elixir**, plus three front-ends
built on it (a LISP reader + evaluator, a JSON parser, and an arithmetic
calculator). It started as an in-progress hobby library and has grown a real
error-reporting system, linear-time parsing, Parsec-style operators, left
recursion, and several DSLs.

- **Tests:** 255 tests + 14 doctests, all passing.
- **Elixir:** `~> 1.12` (developed/tested on 1.20.3, OTP 29). No runtime deps.
- **Layout:** `lib/` (source), `test/` (ExUnit), `examples/` (runnable LISP),
  `bench/` (perf script).

---

## How to run things

```
mix test                 # full suite
mix run bench/bench.exs   # combinator benchmarks (or: elixir bench/bench.exs)
mix lisp FILE.lisp        # evaluate a LISP file
mix lisp                  # LISP REPL
mix format --check-formatted   # enforced by CI
```

CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs the suite on an
Elixir 1.12 / 1.15 / 1.19 / 1.20 matrix, executes every `examples/*.lisp`, and
checks formatting (on 1.20 only — formatter output varies by release).

> **Dev-deps.** `mix.exs` declares dev/test-only tooling (`ex_doc`, `dialyxir`,
> `credo`); none are needed to compile or test the library itself. The versions
> were pinned to 2019 releases that no longer compile on modern Elixir (`credo
> 1.0.4` fails with a `Regex.CompileError` on 1.19), so they were bumped to
> current majors. `mix deps.get && mix test` now works from a clean clone.

---

## Module map

### Core parsing

| Module | File | What it is |
| --- | --- | --- |
| `State` | [lib/state.ex](lib/state.ex#L1) | Position + **unconsumed suffix** (`rest`) for O(1) amortised access. |
| `Combinators` | [lib/combinators.ex](lib/combinators.ex#L1) | The fundamental combinators. |
| `Combinators.Builtin` | [lib/combinators.ex#L368](lib/combinators.ex#L368) | Operators, lexical helpers, derived combinators. |
| `Combinators.Failure` | [lib/failure.ex](lib/failure.ex#L1) | Furthest-failure tracker for error messages. |
| `Combinators.LeftRec` | [lib/left_rec.ex](lib/left_rec.ex#L1) | Packrat memoisation + left-recursion (`rule/2`). |
| `Parser` | [lib/parser.ex](lib/parser.ex#L1) | `parse/2` entry point → `{:ok, tree}` / `{:error, reason}`. |

### DSLs (opt-in sugar)

| Module | File | What it is |
| --- | --- | --- |
| `Combinators.DSL` | [lib/dsl.ex](lib/dsl.ex#L1) | `sequence do…end`, `choice do…end` macros. |
| `Combinators.Expr` | [lib/expr.ex](lib/expr.ex#L1) | Operator-precedence table (`expression/2`). |
| `Combinators.Grammar` | [lib/grammar.ex](lib/grammar.ex#L1) | `use` + `defrule` module DSL. |

### Front-ends

| Module | File | What it is |
| --- | --- | --- |
| `LispParser` | [lib/lisp_parser.ex](lib/lisp_parser.ex#L1) | LISP reader → compact AST. |
| `Evaluator` | [lib/evaluator.ex](lib/evaluator.ex#L1) | Scheme-style interpreter (TCO, REPL). |
| `JsonParser` | [lib/json_parser.ex](lib/json_parser.ex#L1) | JSON → Elixir maps/lists/values. |
| `Calculator` | [lib/calculator.ex](lib/calculator.ex#L1) | Arithmetic, built on the precedence table. |
| `LuaParser` | [lib/lua_parser.ex](lib/lua_parser.ex#L1) | **Complete Lua 5.4** → AST. Grammar spec in [examples/lua.ebnf](examples/lua.ebnf). |
| `UrlParser` | [lib/url_parser.ex](lib/url_parser.ex#L5) | The original tiny URL demo. |
| `Mix.Tasks.Lisp` | [lib/mix/tasks/lisp.ex](lib/mix/tasks/lisp.ex#L1) | `mix lisp` task. |
| `Vortex` | [lib/vortex.ex](lib/vortex.ex#L1) | Leftover generated `hello`. |

---

## The core protocol

A parser is a function `State.t -> {node, State.t} | nil`. `node` is usually
`[label | children]`; a failure is `nil`. Higher-order combinators thread the
`State` and short-circuit on `nil`. Value-producing parsers (via `map`/`~>`,
`bind`, `chainl1`, `expression`) put a plain value where the node would be —
the framework doesn't care what the "node" is.

`State` ([lib/state.ex](lib/state.ex#L1)) carries `string` (original), `rest`
(unconsumed suffix), `offset`, `line`, `column`. `peek/2`
([L34](lib/state.ex#L34)) and `read/2` ([L41](lib/state.ex#L41)) slice a few
graphemes off `rest` and re-point with `binary_part/3`, so cost is proportional
to what's consumed, not the absolute offset. `complete?/1`
([L60](lib/state.ex#L60)) is `rest == ""`.

---

## Combinators reference (with line numbers)

### Fundamentals — `Combinators` ([lib/combinators.ex](lib/combinators.ex#L1))

| Fn | Line | Notes |
| --- | --- | --- |
| `str/1,3` | [L32](lib/combinators.ex#L32) | match a literal |
| `char/1,3` | [L50](lib/combinators.ex#L50) | one char in a regex class (regex compiled once) |
| `any/0,1` | [L72](lib/combinators.ex#L72) | any one char |
| `eof/0,1` | [L89](lib/combinators.ex#L89) | assert end of input |
| `followed_by/1` | [L104](lib/combinators.ex#L104) | positive lookahead |
| `not_followed_by/1` | [L118](lib/combinators.ex#L118) | negative lookahead |
| `opt/1,2` | [L133](lib/combinators.ex#L133) | optional, never fails |
| `seq/1,3` | [L151](lib/combinators.ex#L151) | sequence (prepend+reverse, linear) |
| `rep/2,4` | [L185](lib/combinators.ex#L185) | ≥ n greedy repetition |
| `alt/1` | [L221](lib/combinators.ex#L221) | ordered choice, pass-through |
| `ref/1` | [L234](lib/combinators.ex#L234) | reference a module fn by name |
| `lazy/1` | [L248](lib/combinators.ex#L248) | defer building (breaks build-time recursion) |
| `rule/2` | [L262](lib/combinators.ex#L262) | delegates to `LeftRec.rule/2` |
| `map/2` | [L270](lib/combinators.ex#L270) | transform the node |
| `bind/2` | [L285](lib/combinators.ex#L285) | monadic bind (drives `sequence`) |
| `return/1` | [L299](lib/combinators.ex#L299) | pure parser; `pure/1` alias [L303](lib/combinators.ex#L303) |
| `text/1` | [L311](lib/combinators.ex#L311) | replace node with matched substring |
| `collect_text/1` | [L321](lib/combinators.ex#L321) | concat all string leaves (shared helper) |
| `label/2` | [L334](lib/combinators.ex#L334) | Parsec `<?>` — friendly error name |
| `keep_left/2` | [L348](lib/combinators.ex#L348) | Parsec `<*` |
| `keep_right/2` | [L357](lib/combinators.ex#L357) | Parsec `*>` |

### Operators & derived — `Combinators.Builtin` ([lib/combinators.ex#L368](lib/combinators.ex#L368))

Operators (each is sugar for a named fn; both spellings coexist):

| Op | Fn | Line |
| --- | --- | --- |
| `<\|>` | `alt/1` | [L398](lib/combinators.ex#L398) |
| `~>` | `map/2` | [L415](lib/combinators.ex#L415) |
| `~>>` | `keep_right/2` | [L418](lib/combinators.ex#L418) |
| `<<~` | `keep_left/2` | [L421](lib/combinators.ex#L421) |

> **Elixir operator constraint:** `<$>`, `<*>`, `<?>`, `<*`, `*>` are **syntax
> errors** in Elixir (verified) — the language only allows operators from a
> fixed token set. So those stay as functions (`map`, `keep_*`, `label`). The
> four operators that exist share **one** left-associative precedence level, so
> `a <\|> b ~> f` == `(a <\|> b) ~> f` — parenthesise when mixing.

Whitespace layer (`lexeme` convention — every token eats its *trailing* space,
so a grammar only skips leading space once at the top): `ws/0`, `ws1/0`,
`lexeme/1,2`, `symbol/1,2`, `whitespaced/1,2`. Each takes an optional custom
space consumer, which is how `LispParser` folds `;` comments into whitespace.

Derived/lexical: `optional/1` [L424](lib/combinators.ex#L424), `digit`/`integer`/`digits`
([L426–L444](lib/combinators.ex#L426)), `many/1` [L449](lib/combinators.ex#L449),
`many1/1` [L455](lib/combinators.ex#L455), `between/3` [L461](lib/combinators.ex#L461),
`sep_by1/2` [L468](lib/combinators.ex#L468), `sep_by/2` [L476](lib/combinators.ex#L476),
`one_of/1` [L484](lib/combinators.ex#L484), `none_of/1` [L500](lib/combinators.ex#L500),
`count/2` [L515](lib/combinators.ex#L515), `rep_range/3` [L536](lib/combinators.ex#L536),
`chainl1/2` [L569](lib/combinators.ex#L569), `chainr1/2` [L596](lib/combinators.ex#L596).

---

## Feature deep-dives

### Error reporting — `Combinators.Failure` ([lib/failure.ex](lib/failure.ex#L1))

Process-dictionary tracker of the **furthest** position a parse reached. Leaf
combinators call `record/2` ([L32](lib/failure.ex#L32)) on failure; only the
deepest offset is kept, and same-offset expectations accumulate. `Parser.parse`
([lib/parser.ex#L31](lib/parser.ex#L31)) calls `reset/0` before a run and builds
the message from `deepest/0` ([L70](lib/failure.ex#L70)):

```
{:error, "line 1, column 4: expected \"bar\""}
```

`relabel/2` ([L55](lib/failure.ex#L55)) backs `label/2` — it replaces the
expectation set at a position with one friendly name, *unless* a deeper failure
already exists (so a label never hides an error found after input was consumed).

### Linear-time parsing

The dominant old cost was `String.slice`/`String.length` at an absolute offset
(O(offset) per char → O(n²) parses). Fixed by the `rest`-carrying `State`
above.

> **A second quadratic lurked here until the Lua work.** `State.read/2` still
> called `String.slice(rest, 0, n)`, which walks the *whole* binary to build a
> grapheme view — so a read cost O(remaining input), and a full parse was
> quadratic again. It hid from the old benchmarks because they read from near
> the end of the input. `read/2` and `peek/2` now walk exactly `n` graphemes
> with `String.next_grapheme/1`, and the per-read `String.split(consumed,
> ~r/\R/)` (a regex on every character read) is a byte-pattern match. A single
> read went from ~27 µs at 80 KB remaining to a flat ~0.5 µs, making a 4 000
> statement parse **14.7x** faster (10.5 s → 0.7 s). Guarded by
> "reading a single grapheme is independent of the remaining input size" in
> [test/performance_test.exs](test/performance_test.exs). Secondary: `seq`/`rep`/`count`/`rep_range` build result lists by
prepend+reverse; `char` compiles its class regex once. Benchmarks:
[bench/bench.exs](bench/bench.exs); regression guard:
[test/performance_test.exs](test/performance_test.exs) (parses 20k-element
inputs that would time out under the old code).

### Left recursion — `Combinators.LeftRec` ([lib/left_rec.ex](lib/left_rec.ex#L1))

`rule/2` ([L57](lib/left_rec.ex#L57)) makes **direct** left recursion work
(Warth et al. seed growing, direct case) with packrat memoisation keyed by
`{name, offset}`:

- A self-reference at the same offset returns the current *seed* (initially
  failure → base branch taken).
- The body is re-applied, letting the left-recursive branch extend the previous
  match, until it stops consuming more (`grew?`).
- Results are memoised per run; `Parser.parse` clears the tables via
  `reset/0` ([L42](lib/left_rec.ex#L42)).

So `expr = expr "+" term | term` parses `10-2-3` as `5` (left-assoc). Two
cooperating rules give precedence. **Only direct** LR is grown; indirect cycles
terminate safely but may not grow fully (see limitations).

### `sequence` / `choice` macros — `Combinators.DSL` ([lib/dsl.ex](lib/dsl.ex#L1))

`sequence` ([L35](lib/dsl.ex#L35)) is do-notation for `seq`, desugaring to
`bind`/`return`; the bound pattern is a normal Elixir pattern (destructuring
works). `choice` ([L42](lib/dsl.ex#L42)) is one-alternative-per-line sugar for
`alt`. (The old `choice/1` *function* was removed in favour of this macro; use
`alt/1` for the list form.)

```elixir
sequence do
  _     <- str("(")
  value <- expr()
  _     <- str(")")
  return value
end
```

### Expression precedence table — `Combinators.Expr` ([lib/expr.ex](lib/expr.ex#L1))

`expression/2` ([L39](lib/expr.ex#L39)) builds a layered parser from a table
ordered **tightest-first**, using `chainl1`/`chainr1`/non-assoc per level and
folding prefix/postfix around the term. Descriptors: `infixl` [L45](lib/expr.ex#L45),
`infixr` [L49](lib/expr.ex#L49), `infixn` [L53](lib/expr.ex#L53),
`prefix` [L57](lib/expr.ex#L57), `postfix` [L61](lib/expr.ex#L61). `2^3^2` → 512
(right-assoc). The calculator's whole precedence structure is one such table.

### Grammar module DSL — `Combinators.Grammar` ([lib/grammar.ex](lib/grammar.ex#L1))

`use Combinators.Grammar` + `defrule` ([L47](lib/grammar.ex#L47)). Each
`defrule :name do … end` expands to `def name, do: Combinators.rule(:name, fn ->
… end)`, so rules are memoised, may be left-recursive, and reference each other
just by calling `name()` — **no `lazy`, no `rule()` boilerplate**.

---

## Front-ends

### LISP — `LispParser` + `Evaluator`

- **`LispParser`** ([lib/lisp_parser.ex](lib/lisp_parser.ex#L1)): `parse/1`
  [L74](lib/lisp_parser.ex#L74), `parse_one/1` [L86](lib/lisp_parser.ex#L86),
  `parse!/1` [L100](lib/lisp_parser.ex#L100). Reads numbers, strings (with
  escapes), booleans, symbols, lists, quote `'`, quasiquote `` ` `` `,` `,@`
  ([L136–L143](lib/lisp_parser.ex#L136)), and `;` comments into a compact AST
  (`{:list, [...]}`, `{:number, n}`, `{:quasiquote, …}`, etc.).
- **`Evaluator`** ([lib/evaluator.ex](lib/evaluator.ex#L1)): Scheme-style
  interpreter. Special forms at [L41](lib/evaluator.ex#L41). **Trampolined**
  evaluation (`eval_ast`/`step` at [L173](lib/evaluator.ex#L173)/[L180](lib/evaluator.ex#L180))
  gives **tail-call optimization** — a 1M-iteration tail loop returns cleanly.
  Quasiquote expansion `quasi/3` at [L366](lib/evaluator.ex#L366). Global scope
  is an `Agent`; local scopes are immutable frames. API: `eval/1`
  [L50](lib/evaluator.ex#L50), `eval_file/1` [L75](lib/evaluator.ex#L75),
  persistent-env `start_env`/`eval_string`/`stop_env`
  ([L84](lib/evaluator.ex#L84)/[L99](lib/evaluator.ex#L99)/[L91](lib/evaluator.ex#L91)),
  `repl/0` [L118](lib/evaluator.ex#L118). Supports `quote`, `quasiquote`, `if`,
  `cond`, `when`, `unless`, `define`, `lambda`, `let`, `let*`, `and`, `or`,
  `begin`, `set!` + a numeric/list/higher-order stdlib.

### JSON — `JsonParser` ([lib/json_parser.ex](lib/json_parser.ex#L1))

`parse/1` [L35](lib/json_parser.ex#L35), `parse!/1` [L48](lib/json_parser.ex#L48).
Objects→maps, arrays→lists, `true/false/null`→`true/false/nil`, full string
escapes incl. `\uXXXX`, int/float/exponent numbers. Grammar builds a labelled
tree, then a `to_value` transform walks it (same pattern as the LISP AST).

### Lua — `LuaParser` ([lib/lua_parser.ex](lib/lua_parser.ex#L1))

`parse/1` / `parse!/1`. Covers the **whole** Lua 5.4 grammar; the spec it was
written against is checked in at [examples/lua.ebnf](examples/lua.ebnf), and
[examples/showcase.lua](examples/showcase.lua) is a runnable chunk exercising
most of the language. Worth knowing:

- **It uses nearly the whole library**: `defrule` for the ~25 mutually
  recursive rules, `Combinators.Expr` for the precedence table, `bind/2` for
  long-bracket level matching (`[==[ … ]==]` — *not* context-free), `lexeme/2`
  with a custom space consumer so comments count as whitespace.
- **`^` needed a hand-written rule.** Its precedence is asymmetric — tighter
  than a unary operator on its left (`-x^2` is `-(x^2)`) but its right operand
  parses at unary precedence (`2^-3` is valid). One `Expr` level can't express
  that, so `power`/`unary_exp` do it directly.
- **Operator prefixes need lookahead.** `Expr`'s bare-string operators match
  greedily, so `<` would eat the `<` of `<=`, and `-` would start a `--`
  comment. `op/1` wraps conflicting tokens in `not_followed_by`.
- **Differential-tested against `luac -p`** over 106 Neovim files: zero
  syntactic disagreements. Where `luac` rejects and this accepts, it is always
  a *semantic* check needing scope analysis — `break` outside a loop, assigning
  to a `<const>`, `goto` to an invisible label. A grammar cannot catch those.

### Calculator — `Calculator` ([lib/calculator.ex](lib/calculator.ex#L1))

`eval/1` [L38](lib/calculator.ex#L38), `eval!/1` [L53](lib/calculator.ex#L53).
Parses **and** evaluates in one pass. The precedence structure is a single
`operator_table` [L63](lib/calculator.ex#L63) fed to `Combinators.Expr`. Uses
`choice`/`sequence` for the atom, `~>`/`label` for numbers, and rescues
`ArithmeticError` (division by zero).

---

## Tests (`test/`)

| File | Covers |
| --- | --- |
| [combinators_test.exs](test/combinators_test.exs) | original core combinators |
| [combinators_derived_test.exs](test/combinators_derived_test.exs) | `any`, `map`, `lazy`, `many*`, `sep_by*`, `between`, `one_of`/`none_of` |
| [parser_test.exs](test/parser_test.exs) | `Parser.parse` ok/error/partial |
| [parser_errors_test.exs](test/parser_errors_test.exs) | furthest-failure messages, `eof`, lookahead, `count`, `rep_range` |
| [operators_test.exs](test/operators_test.exs) | `<\|>` `~>` `~>>` `<<~`, `label`, `keep_*`, `optional` |
| [performance_test.exs](test/performance_test.exs) | 20k-element linear-time guards |
| [left_recursion_test.exs](test/left_recursion_test.exs) | **left-recursive** grammars: `sum`, `expr/term/factor`, node nesting, memo reset |
| [indirect_left_recursion_test.exs](test/indirect_left_recursion_test.exs) | **indirect** cycles: termination, base case, measured growth limits |
| [lexeme_test.exs](test/lexeme_test.exs) | `ws`/`ws1`/`lexeme`/`symbol`/`whitespaced`, CRLF handling |
| [lua_parser_test.exs](test/lua_parser_test.exs) | Lua 5.4: literals, precedence, every statement form, rejects |
| [dsl_test.exs](test/dsl_test.exs) | `sequence`/`choice` macros |
| [expr_test.exs](test/expr_test.exs) | precedence table: L/R/non-assoc, prefix/postfix |
| [grammar_test.exs](test/grammar_test.exs) | `defrule` grammar (also left-recursive) |
| [lisp_parser_test.exs](test/lisp_parser_test.exs) | LISP reader incl. quasiquote |
| [evaluator_test.exs](test/evaluator_test.exs) | evaluator core + example programs |
| [evaluator_extras_test.exs](test/evaluator_extras_test.exs) | quasiquote, when/unless, TCO (1M), persistent env |
| [json_parser_test.exs](test/json_parser_test.exs) | JSON incl. nesting, escapes, unicode, errors |
| [calculator_test.exs](test/calculator_test.exs) | precedence, associativity, unary, errors |
| [url_parser_test.exs](test/url_parser_test.exs) | URL demo |
| [vortex_test.exs](test/vortex_test.exs) | generated `hello` |

Left-recursive grammar tests specifically: `test/left_recursion_test.exs`
(`sum = sum "+" num | …` at [L11](test/left_recursion_test.exs#L11);
`expr/term/factor` at [L21](test/left_recursion_test.exs#L21)) and
`test/grammar_test.exs` (`Arith` module, `defrule :expr` at
[L11](test/grammar_test.exs#L11)).

## Examples (`examples/`) & bench

Runnable LISP with expected results in [examples/README.md](examples/README.md):
`quicksort.lisp`, `factorial.lisp`, `fibonacci.lisp`, `higher_order.lisp`,
`classics.lisp`, `quasiquote.lisp`. Benchmark script: `bench/bench.exs`.

---

## History (merged PRs)

1. **#1** — Finish combinator lib + LISP parser/evaluator + examples (original build-out).
2. **#2** — Furthest-failure error reporting + `eof`/lookahead/`count`/`rep_range`.
3. **#3** — Linear-time parsing (`rest`-carrying `State`, prepend+reverse, regex precompile).
4. **#4** — `JsonParser` + `Calculator` + `text`/`chainl1`/`chainr1`.
5. **#5** — LISP quasiquote, `when`/`unless`, tail calls, REPL, `mix lisp`.
6. **#6** — Parsec-style operators (`<\|>` `~>` `~>>` `<<~`) + `label`.
7. **#7** — Direct left recursion (`Combinators.LeftRec`).
8. **#8** — `sequence`/`choice` block macros (`Combinators.DSL`).
9. **#9** — Operator-precedence table (`Combinators.Expr`).
10. **#10** — Grammar module DSL (`Combinators.Grammar`, `defrule`).
11. **#11** — Toolchain fix: bump dev deps, `import Config`, Elixir `~> 1.12`.
12. **#12** — `lexeme`/`symbol`/`whitespaced` layer; removed manual `ws()`
    threading from JSON/calculator/LISP/`Expr`. Fixed a pre-existing CRLF bug
    (`"\r\n"` is one grapheme, so `one_of/1` never matched it).
13. **#13** — Tests pinning indirect left-recursion behaviour.
14. **#14** — GitHub Actions CI (Elixir 1.12/1.15/1.19 matrix) + `mix format`
    pass over the repo.
15. **#15** — Bump dev toolchain to Elixir 1.20.3 / OTP 29.0.5; CI matrix gains
    a 1.20 row.
16. **#16** — `LuaParser`: complete Lua 5.4. Fixed the second `State` quadratic
    found while scaling it (see "Linear-time parsing").

---

## Known limitations & next ideas

**Limitations / gaps**
- **Indirect** left recursion isn't grown (only direct), now pinned down by
  [test/indirect_left_recursion_test.exs](test/indirect_left_recursion_test.exs).
  Measured behaviour: every cycle **terminates** and never returns a wrong
  answer (ungrowable input is `{:error, _}`, not a silent partial parse). An
  *alias* cycle (`a -> b -> a`, where `b` consumes nothing) never grows past the
  base case; a *mutual* cycle where both rules consume (`x -> y -> x`) grows
  exactly **one** level, then stops; a three-rule cycle doesn't grow. Those
  limits are asserted, so adding indirect support is a visible change.
- There are now **two idioms** for expression grammars: left-recursive `rule/2`
  and the `chainl1`/`expression` table. Both are tested and correct; if you want
  one blessed way, that's a cleanup decision.
- `Evaluator` `define` always targets the global scope (internal defines leak
  global). `set!` on a local binding raises (only globals mutate).
- Scannerless/string-only: `State` is tied to binary input; no token-stream mode.
- Error messages can show raw whitespace char-classes (e.g. `one of " \t\n\r"`);
  cosmetic. `label/2` is the workaround.

**Candidate next steps (discussed, not built)**
- Error **recovery** (skip to a sync token, collect multiple errors).
- Generalise combinators over **token streams** (two-phase lexer→parser).
- Packrat memoisation for *all* combinators (not just `rule/2`).
- Publish to Hex: ExDoc, GitHub Actions CI, Dialyzer specs (deps already declared).
- Property-based tests / fuzzing (StreamData).
- More front-ends (regex engine, CSV, TOML) to exercise the library.

---

## Conventions

- Parsers are plain functions; failure is `nil`; nodes are `[label | children]`
  (or a plain value for value-producing parsers).
- `import Combinators` + `import Combinators.Builtin` for the full toolkit; add
  `import Combinators.DSL` / `Combinators.Expr` / `use Combinators.Grammar` for
  the sugar.
- Grammars that recurse: use `lazy/1` for plain recursion, or `rule/2` /
  `defrule` for left recursion + memoisation.
- Run something end-to-end before trusting it — every feature here was smoke-
  tested against real input, then locked in with ExUnit.
